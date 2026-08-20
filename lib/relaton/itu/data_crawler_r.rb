require "mechanize"
require_relative "../itu"
require_relative "data_parser_r"

module Relaton
  module Itu
    # PROTOTYPE (issue #75) — a replacement for the decommissioned RunSearch bulk
    # enumeration, proven on one series.
    #
    # ITU-R metadata is still fully server-rendered under `/pub` + `/rec`, in
    # three levels — Recommendations:
    #
    #   /pub/R-REC/en                     -> the 16 series
    #   /rec/R-REC-BO/en                  -> one row per document (54 for BO)
    #   /rec/R-REC-BO.1130/en             -> one row per edition (Main + Previous)
    #   /rec/R-REC-BO.1130-5-202602-I/en  -> approval day + the PDF href
    #
    # and Reports, the same shape under a different root (see FAMILIES):
    #
    #   /pub/R-REP/en                     -> the 14 report series
    #   /pub/R-REP-BO/en                  -> one row per document (36 for BO)
    #   /pub/R-REP-BO.1227/en             -> one row per edition
    #   /pub/R-REP-BO.1227-2-1998/en      -> the files' posted date + PDF href
    #
    # It is **not** wired into DataFetcher#fetch and nothing under lib/ requires
    # it: reaching it takes an explicit `require`, so no scheduled crawl can run
    # an unproven harvester. Promotion path, once the numbers justify it — note
    # the write goes through DataMergeR, never straight to #write_file, so a
    # partial harvest can't overwrite what it cannot see:
    #
    #   require "relaton/itu/data_merge_r"
    #   fetcher = Relaton::Itu::DataFetcher.new("data", "yaml")
    #   crawler = Relaton::Itu::DataCrawlerR.new
    #   items = crawler.harvest("BO") + crawler.harvest("BO", family: "R-REP")
    #   Relaton::Itu::DataMergeR.write_all items, fetcher
    #   fetcher.index.save
    #
    class DataCrawlerR
      DOMAIN = "https://www.itu.int".freeze

      # Both families are the same three-level tree with different URL roots and
      # a different date field. `date:` is the substantive difference, not a
      # detail: a Recommendation page publishes only its **approval** date,
      # while a Report page carries the "Posted" date of its files — which is
      # the **publication** date the preserved records hold. So a harvested
      # Report reproduces the published `date:`, and a harvested Recommendation
      # cannot (see DataMergeR, which is why the merge never rewrites one).
      FAMILIES = {
        "R-REC" => {
          index: "#{DOMAIN}/pub/R-REC/en",
          page: "#{DOMAIN}/rec/%<id>s/en",
          pdf: "#{DOMAIN}/dms_pubrec/itu-r/rec/%<series>s/%<id>s!!PDF-E.pdf",
          date: :approved,
          group: :series,
        }.freeze,
        "R-REP" => {
          index: "#{DOMAIN}/pub/R-REP/en",
          page: "#{DOMAIN}/pub/%<id>s/en",
          pdf: "#{DOMAIN}/dms_pub/itu-r/opb/rep/%<id>s-PDF-E.pdf",
          date: :posted,
          group: :series,
        }.freeze,
        # Questions nest one level deeper: the family index lists **study
        # groups** (R-QUE-SG01), not series letters. No `pdf:` template — a
        # Question edition page usually offers no PDF of its own (verified on
        # R-QUE-SG01.202-2-2002), and deriving a URL that 404s is worse than
        # leaving the record sourceless.
        "R-QUE" => {
          index: "#{DOMAIN}/pub/R-QUE/en",
          page: "#{DOMAIN}/pub/%<id>s/en",
          date: :posted,
          group: :sub_index,
        }.freeze,
        # Handbooks are flat like Resolutions, but they publish less per page
        # than any other family, so two things move: the **date** comes from the
        # id (an edition page carries no posted date, and the displayed codes
        # disagree with each other — `R-HDB-43-2013` renders "2014" against its
        # siblings' "2026" and "Edition of 2002"), and the **title** comes from
        # the level-1 row, the only place ITU prints it.
        "R-HDB" => {
          index: "#{DOMAIN}/pub/R-HDB/en",
          page: "#{DOMAIN}/pub/%<id>s/en",
          pdf: "#{DOMAIN}/dms_pub/itu-r/opb/hdb/%<id>s-PDF-E.pdf",
          date: :id,
          title: :document,
          group: :flat,
        }.freeze,
        # Resolutions are **flat**: /pub/R-RES/en links all 75 documents
        # directly, with no grouping level at all.
        "R-RES" => {
          index: "#{DOMAIN}/pub/R-RES/en",
          page: "#{DOMAIN}/pub/%<id>s/en",
          pdf: "#{DOMAIN}/dms_pub/itu-r/opb/res/%<id>s-PDF-E.pdf",
          date: :posted,
          group: :flat,
        }.freeze,
      }.freeze
      DEFAULT_FAMILY = "R-REC".freeze

      # Every level is addressable by its id. The pages' own links are
      # `./recommendation.asp?…&parent=<id>` / `publications.aspx?…&parent=<id>`,
      # which resolve against the series directory and do NOT reach the
      # canonical page — so the id is extracted from `parent=` and the URL
      # rebuilt, never followed.
      PARENT_RE = /[?&]parent=(?<id>[^"&\s]+)/.freeze
      APPROVED_RE = /Approved in\s*(\d{4}-\d{2}(?:-\d{2})?)/.freeze
      # A Report edition page dates each downloadable file ("Posted"). The day is
      # the file's posting stamp; the corpus records these at month precision.
      POSTED_RE = /\b((?:19|20)\d{2}-\d{2})-\d{2}\b/.freeze
      # "R-REC-BO.1130-3-200007-S" -> "2000-07"
      ID_DATE_RE = /-(\d{4})(\d{2})-[A-Za-z]+\z/.freeze
      # "R-REP-BO.1227-2-1998" -> "1998"
      ID_YEAR_RE = /-((?:19|20)\d{2})\z/.freeze
      # Where a throttled /pub request lands instead of erroring.
      NOTFOUND = "notfound.aspx".freeze
      RETRIES = 3
      RETRY_BACKOFF = 5 # seconds, multiplied by the attempt number

      # @param agent [Mechanize] one agent per crawler (Mechanize is not
      #   thread-safe, so a parallel harvester needs one per worker)
      # @param delay [Numeric] politeness pause before each request — www.itu.int
      #   sits behind an F5 WAF that throttles, and a full crawl is ~10^4 pages
      def initialize(agent: self.class.agent, delay: 0.5)
        @agent = agent
        @delay = delay
      end

      # Same hardening as DataFetcher#rec_agent: the browser UA is mandatory (the
      # WAF rejects non-browser clients) and max_history keeps a long crawl from
      # retaining every page it has read.
      def self.agent
        Mechanize.new.tap do |a|
          a.user_agent_alias = "Mac Safari"
          a.max_history = 1
          a.open_timeout = 15
          a.read_timeout = 60
        end
      end

      # The grouping level between a family index and its documents. Three
      # topologies, all real:
      #
      #   :series     R-REC/R-REP — 16 and 14 series letters (BO, BR, …)
      #   :sub_index  R-QUE       — 6 study groups (SG01, SG03, …)
      #   :flat       R-RES       — none; the index links all 75 documents
      #
      # A flat family yields a single nil group so the walk below stays one
      # shape: index -> group -> document -> edition.
      #
      # @param family [String]
      # @return [Array<String, nil>]
      def series(family = DEFAULT_FAMILY)
        conf = config(family)
        return [nil] if conf[:group] == :flat

        pattern = conf[:group] == :sub_index ? "(SG\\d+)" : "([A-Z]+)"
        found = get(conf[:index]).search("//a").filter_map do |a|
          a[:href].to_s[%r{/(?:rec|pub)/#{Regexp.escape family}-#{pattern}/en\z}, 1]
        end.uniq
        warn_if_empty found, "#{family} groups"
      end

      # Level 1 — every document in a series.
      #
      # @param series [String] e.g. "BO"
      # @param family [String] "R-REC" or "R-REP"
      # @return [Array<Hash>] { id:, code:, title: }
      def documents(series, family: DEFAULT_FAMILY)
        conf = config(family)
        # A flat family lists its documents on the family index itself; the
        # others list them on the group page.
        url, prefix = series ? [page_url("#{family}-#{series}"), "#{family}-#{series}."] : [conf[:index], "#{family}-"]
        found = rows(url).filter_map do |id, anchor, cells|
          # Every one of these pages links itself (parent=R-REC-BO,
          # parent=R-QUE-SG01) for the language switcher, and a flat index links
          # only documents — so the prefix test is what separates the two.
          next unless id.start_with?(prefix) && id != prefix.chomp(".")

          # The Handbook index lists *titles* where every other family lists
          # numbers — its number is in the id alone and its title cell is empty.
          name = squish(anchor.text)
          { id: id, code: name, title: conf[:title] == :document ? name : title_text(cells[1]) }
        end
        warn_if_empty found, "documents in #{series ? "#{family}-#{series}" : family}"
      end

      # Level 2 — every edition of a document ("Main" first, then "Previous
      # versions"; the page is already newest-first).
      #
      # @param doc_id [String] e.g. "R-REC-BO.1130"
      # @return [Array<Hash>] { id:, code:, title:, status: }
      def editions(doc_id)
        number = doc_id[/\AR-[A-Z]+-(.+)\z/, 1]
        found = rows(page_url(doc_id)).filter_map do |id, anchor, cells|
          next unless id.start_with? "#{doc_id}-" # skip the page's self-link

          code = squish(anchor.text)
          # An edition's code must be the document's own number. ITU lists a
          # second row for some editions under a `…-P` id whose displayed Number
          # is the associated *Question* (`/rec/R-REC-M.2083/en` shows both
          # "M.2083-0 (09/2015)" and "M.5/BL/22 (09/2015)" for one edition) —
          # taking that at face value mints a Recommendation docid out of a
          # question number. Only the `/rec` pages carry those rows, and only
          # there does the code start with the document number: a Resolution
          # renders "Res.1-9 (2023)" against the id `R-RES-R.1-9-2023`.
          next if family_of(doc_id) == "R-REC" && !code.start_with?(number)

          { id: id, code: code, title: title_text(cells[1]), status: squish(cells[2]&.text) }
        end
        # A Handbook edition is listed twice — once with an empty code, once with
        # its year — so keep the richer row per id rather than harvesting the
        # same edition twice.
        found = found.group_by { |e| e[:id] }.map { |_, dupes| dupes.max_by { |e| e[:code].to_s.size } }
        warn_if_empty found, "editions of #{doc_id}"
      end

      # Level 3 — the per-edition page. One request per edition, so this is what
      # makes a full crawl expensive; it buys the day-precision approval date and
      # a PDF href read off the page instead of derived from the id.
      #
      # @param edition_id [String] e.g. "R-REC-BO.1130-5-202602-I"
      # @return [Hash] { date:, pdf: }
      def edition(edition_id)
        page = get(page_url(edition_id))
        # Anchored on the edition id, which is what makes "no PDF ⇒ no source"
        # true. The link shape differs per family ("…!!PDF-E.pdf" for a rec,
        # "…-PDF-E.pdf" for a report) and every /pub page carries a QUICK LINKS
        # sidebar whose Publication Catalogue entry is itself a `…-PDF-E.pdf` —
        # an unanchored match would hand that catalogue URL to any report
        # edition that has no English PDF of its own. Resolved against the page,
        # not concatenated: ITU serves root-relative hrefs today, but an
        # absolute one would give "https://www.itu.inthttps://…".
        # `.pdf`-terminated, because /pub pages also carry an "add to cart"
        # control whose href is `javascript:addcart(…,'R-REP-BT.2526-1-2024-PDF-E',…)`
        # — it contains both the edition id and PDF-E, and feeding it to
        # URI#merge raises URI::InvalidURIError, which once killed a whole series.
        href = page.search("//a[contains(@href,'#{edition_id}') and contains(@href,'PDF-E')]")
                   .map { |a| a[:href].to_s.strip }
                   .find { |h| h.end_with? ".pdf" }
        { date: page_date(page, edition_id), pdf: href && page.uri.merge(href).to_s }
      end

      # End-to-end: a series -> parsed ItemData, one per edition.
      #
      # @param series [String] e.g. "BO"
      # @param family [String] "R-REC" or "R-REP"
      # @param only [Array<String>, nil] restrict to these document ids (specs,
      #   sampling runs)
      # @param deep [Boolean] fetch level 3. false costs `1 + documents` requests
      #   and yields month-precision dates and a derived PDF URL; true adds one
      #   request per edition for the page's own date and PDF href.
      # @param errors [Hash] shared error tally, as DataParserR expects
      # @return [Array<Relaton::Itu::ItemData>]
      def harvest(series, family: DEFAULT_FAMILY, only: nil, deep: true, errors: Hash.new(true), skip: nil)
        docs = documents(series, family: family)
        docs = docs.select { |d| only.include? d[:id] } if only
        # A Handbook edition inherits the document's title (`title: :document`):
        # its own row shows a year and nothing else, so this is the only chance
        # to carry the title down — the level-3 fetch never sees the index.
        inherited = config(family)[:title] == :document
        editions = docs.flat_map do |d|
          editions(d[:id]).map do |ed|
            ed.merge(family: family_of(ed[:id]), **(inherited ? { title: d[:title] } : {}))
          end
        end
        # `skip` is what makes a top-up cheap: it decides from the level-2 row,
        # before the per-edition page — the expensive half — is ever requested.
        editions = editions.reject { |ed| skip.call ed } if skip
        editions.filter_map { |ed| DataParserR.parse(row(ed, deep: deep), errors) }
      end

      private

      # In deep mode the edition page is the **authority**: an edition that
      # offers no `!!PDF-E.pdf` (older ones are Word-only) gets no source rather
      # than a guessed URL that 404s, and a page that came back empty — ITU does
      # serve truncated 200s — is logged instead of being silently backfilled
      # with shallow data, which would make a degraded deep crawl look like a
      # successful one. The derived values are the *shallow* mode's answer.
      #
      # @param ed [Hash] a level-2 row
      # @return [Hash] the normalized row DataParserR consumes
      def row(ed, deep:)
        return ed.merge(base_row(ed), date: id_date(ed[:id]), pdf: pdf_url(ed[:id])) unless deep

        detail = edition(ed[:id])
        # A family whose date lives in the id (Handbooks) is expected to find
        # none on the page; for the others a missing date means a degraded fetch.
        if detail[:date].nil? && config(family_of(ed[:id]))[:date] != :id
          Util.warn "No date on #{page_url ed[:id]} — falling back to the id's date"
        end
        ed.merge(base_row(ed), date: detail[:date] || id_date(ed[:id]), pdf: detail[:pdf])
      end

      # @param ed [Hash]
      # @return [Hash]
      def base_row(ed)
        { family: family_of(ed[:id]), url: page_url(ed[:id]) }
      end

      # @param family [String]
      # @return [Hash] the family's URL templates and date field
      # @raise [ArgumentError] for a family this crawler doesn't implement
      def config(family)
        FAMILIES[family] or
          raise ArgumentError, "unknown ITU-R family #{family.inspect} (known: #{FAMILIES.keys.join ', '})"
      end

      # Every id names its own family, so the level-2/3 methods take an id alone.
      #
      # @param id [String] e.g. "R-REP-BO.1227-2-1998"
      # @return [String] e.g. "R-REP"
      def family_of(id)
        id.to_s[/\AR-[A-Z]+/].to_s
      end

      # @param id [String]
      # @return [String]
      def page_url(id)
        format config(family_of(id))[:page], id: id
      end

      # Recommendation pages carry an approval date; report pages date each
      # downloadable file instead ("Posted"), which is the publication date the
      # corpus records — at month precision, so the day is dropped.
      #
      # @param page [Mechanize::Page]
      # @param id [String]
      # @return [String, nil]
      def page_date(page, id)
        case config(family_of(id))[:date]
        when :approved then page_text(page)[APPROVED_RE, 1]
        when :posted then posted_date(page, id)
        # :id — the page has no date to offer, so #row falls back to the id's
        # year without treating it as a degraded crawl.
        end
      end

      # A report's files can be re-posted after publication, in which case the
      # posted date is no longer the publication date the id names. Say so
      # rather than quietly dating the record by a re-upload.
      #
      # @param page [Mechanize::Page]
      # @param id [String]
      # @return [String, nil]
      def posted_date(page, id)
        date = page_text(page)[POSTED_RE, 1]
        year = id[ID_YEAR_RE, 1]
        if date && year && date[0, 4] != year
          Util.warn "Posted date #{date} on #{page_url id} disagrees with the id's year #{year}"
        end
        date
      end

      # The decoded document text minus scripts: the raw body is the response's
      # bytes (Latin-1 here, ASCII-8BIT when replayed from a cassette), and the
      # SharePoint chrome embeds JavaScript full of date literals that a bare
      # date match would find first.
      #
      # @param page [Mechanize::Page]
      # @return [String]
      def page_text(page)
        doc = page.parser.dup
        doc.search("script", "style").each(&:remove)
        squish doc.text
      end

      # An ITU restyle would leave every level matching nothing, and the crawl
      # would return an empty corpus that looks like a successful run — the
      # silent failure ITU_R_DISABLED exists to prevent for RunSearch. Say so.
      #
      # @param found [Array] the level's rows
      # @param what [String] what was being enumerated
      # @return [Array] found, unchanged
      def warn_if_empty(found, what)
        Util.warn "ITU-R crawl: no #{what} found — the page layout may have changed" if found.empty?
        found
      end

      # Shallow mode's date. A Recommendation id ends in YYYYMM (the displayed
      # code renders pre-2000 editions with a two-digit year, so the id is the
      # only unambiguous source); a Report id ends in the publication year, which
      # gives no month.
      #
      # @param id [String]
      # @return [String, nil]
      def id_date(id)
        m = id.match(ID_DATE_RE)
        return "#{m[1]}-#{m[2]}" if m

        id[ID_YEAR_RE, 1]
      end

      # nil rather than a malformed URL when the series can't be read off the id
      # — DataParserR then records the missing source in the error tally instead
      # of writing `…/rec//R-REC-…` into the data file.
      #
      # @param id [String]
      # @return [String, nil]
      def pdf_url(id)
        template = config(family_of(id))[:pdf]
        return nil unless template # R-QUE editions rarely have one; never guess
        return format(template, id: id) unless template.include? "%<series>s"

        series = id[/-([A-Za-z]+)\./, 1]
        series && format(template, series: series.downcase, id: id)
      end

      # Every level's table rows share one shape: a `parent=`-linked anchor in
      # the first cell, the title in the second.
      #
      # @param url [String]
      # @return [Array<Array(String, Nokogiri::XML::Element, Nokogiri::XML::NodeSet)>]
      def rows(url)
        get(url).search("//a[contains(@href,'parent=R-')]").filter_map do |a|
          id = a[:href].to_s[PARENT_RE, :id]
          tr = a.ancestors("tr").first
          [id, a, tr.search("td")] if id && tr
        end
      end

      # The title cell carries an optional red annotation ("Note - Suppressed on
      # …"), which is not part of the title.
      #
      # @param cell [Nokogiri::XML::Element, nil]
      # @return [String]
      def title_text(cell)
        return "" unless cell

        cell = cell.dup
        cell.search("font").each(&:remove)
        squish(cell.text)
      end

      # The cells are padded with `&nbsp;`, which `\s` does not match — so the
      # non-breaking spaces are folded in before collapsing. `scrub` first: the
      # /rec pages declare no charset in Content-Type, so a page whose encoding
      # Nokogiri sniffs as UTF-8 can hand back Latin-1 bytes, and `gsub` on an
      # invalid-encoding String raises — which would kill the whole series.
      #
      # @param text [String, nil]
      # @return [String]
      def squish(text)
        text.to_s.scrub.tr(" ", " ").gsub(/\s+/, " ").strip
      end

      # Retried, because a corpus-scale crawl *will* be throttled: measured over
      # a 49-minute full run, ITU rate-limits `/rec` with HTTP 503 and `/pub`
      # with a **302 to `/en/publications/pages/notfound.aspx`** — a soft block
      # that is indistinguishable from "no such document" unless you look. That
      # second form silently emptied all 14 report series of one run. So a
      # notfound landing is treated as a retryable failure like any 5xx, and
      # only a persistent one raises.
      #
      # @param url [String]
      # @return [Mechanize::Page]
      # @raise [Relaton::RequestError] after RETRIES attempts
      def get(url)
        attempt = 0
        begin
          attempt += 1
          sleep @delay if @delay.to_f.positive?
          page = @agent.get url
          raise Mechanize::ResponseCodeError.new(page), "redirected to notfound" if notfound? page

          page
        rescue Mechanize::ResponseCodeError, SocketError, Timeout::Error, Errno::ECONNRESET,
               EOFError, Net::ProtocolError, OpenSSL::SSL::SSLError => e
          if attempt <= RETRIES
            Util.warn "ITU-R crawl: #{url} failed (#{e.message}); retry #{attempt}/#{RETRIES} in #{backoff attempt}s"
            sleep backoff(attempt)
            retry
          end
          raise Relaton::RequestError, "Could not access #{url}: #{e.message}"
        end
      end

      # @param page [Mechanize::Page]
      # @return [Boolean]
      def notfound?(page)
        page.uri.to_s.include? NOTFOUND
      end

      # Linear backoff — the block is a rate limit, so the point is to wait out
      # a window, not to hammer a dead host.
      #
      # @param attempt [Integer]
      # @return [Integer] seconds
      def backoff(attempt)
        attempt * RETRY_BACKOFF
      end
    end
  end
end
