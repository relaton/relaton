# frozen_string_literal: true

require "English"
require "fileutils"
require "ferrum"
require "nokogiri"
require "pubid"
require "relaton/index"
require "relaton/bib"
require "relaton/core/data_fetcher"
require_relative "../cie"

module Relaton
  module Cie
    # Thin Ferrum-backed HTTP agent that mimics the Mechanize#get interface
    # used elsewhere in DataFetcher. Drives headless Chrome with stealth
    # tweaks so the CIE catalogue host (Cloudflare-protected accuristech)
    # serves real HTML instead of a "Just a moment..." challenge.
    class BrowserAgent
      UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
           "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
      CHALLENGE_MARKERS = ["Just a moment", "challenge-platform"].freeze
      MAX_CHALLENGE_WAIT = 30

      # Raised when the Cloudflare challenge ("Just a moment…") is still showing
      # after MAX_CHALLENGE_WAIT seconds. It's a retriable signal (see
      # DataFetcher::RETRIABLE_ERRORS): rather than parse the challenge HTML as a
      # document, the caller (#time_req) backs the worker off and retries.
      class ChallengeError < StandardError; end

      def initialize
        @browser = Ferrum::Browser.new(
          headless: true,
          timeout: 90,
          process_timeout: 90,
          window_size: [1366, 768],
          browser_options: {
            "disable-blink-features" => "AutomationControlled",
            "disable-quic" => nil,
            "no-sandbox" => nil
          }
        )
        @browser.headers.set(
          "Accept-Language" => "en-US,en;q=0.9",
          "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9," \
                      "image/webp,*/*;q=0.8",
          "User-Agent" => UA
        )
        # Pre-mask the most common headless-Chrome tells before any page JS runs.
        @browser.evaluate_on_new_document(<<~JS)
          Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
          Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
          Object.defineProperty(navigator, 'plugins', { get: () => [1,2,3,4,5] });
          window.chrome = { runtime: {} };
        JS
      end

      def get(url)
        @browser.go_to(url)
        wait_for_challenge
        Nokogiri::HTML(@browser.body)
      end

      def quit
        @browser&.quit
      ensure
        @browser = nil
      end

      private

      def wait_for_challenge
        MAX_CHALLENGE_WAIT.times do
          return unless CHALLENGE_MARKERS.any? { |m| @browser.body.include?(m) }

          sleep 1
        end
        raise ChallengeError, "Cloudflare challenge did not clear after #{MAX_CHALLENGE_WAIT}s"
      end
    end

    class DataFetcher < Relaton::Core::DataFetcher
      URL = "https://www.techstreet.com/cie/searches/31156444?page=1&per_page=100"

      # Default worker-pool size for the parallel detail-fetch phase. Kept small
      # so N stealth Chrome instances don't burst requests fast enough to trip
      # Cloudflare; tune via RELATON_CIE_CONCURRENCY (see .concurrency).
      DEFAULT_CONCURRENCY = 5

      # Per-worker pacing bounds (seconds). Each worker starts at BASE_GAP and
      # doubles its own gap up to MAX_GAP on trouble (see Pacing / #time_req).
      BASE_GAP = 1
      MAX_GAP = 32

      # Number of detail-fetch worker threads. Tunable via env var so
      # relaton-data-cie's crawler workflow can dial it up for speed or down to
      # lighten load on techstreet without a code change. Never below 1.
      def self.concurrency
        [(ENV["RELATON_CIE_CONCURRENCY"] || DEFAULT_CONCURRENCY).to_i, 1].max
      end

      def initialize(output, format)
        super
        # Guards the shared bookkeeping (@files, @errors, @seen) and the index
        # mutation while workers fetch detail pages in parallel. The slow
        # agent.get runs outside this lock; only the cheap build+write is held.
        @mutex = Mutex.new
        # output file => catalogue position of the hit that last claimed it, so a
        # duplicate primary id resolves to the same last-by-position winner the
        # serial crawl would pick, regardless of worker completion order.
        @seen = {}
      end

      # Factory for a fresh stealth browser agent. The pool builds one per worker
      # (each its own Chrome, each with the full UA/header/`navigator` masking);
      # #agent memoizes a single one for the serial listing phase. Specs stub
      # this so one double can back every worker.
      def build_agent
        BrowserAgent.new
      end

      def agent
        @agent ||= build_agent
      end

      # Per-worker adaptive request pacing. Replaces the old single global 4 s
      # gap: each worker owns one Pacing, starts at BASE_GAP, and doubles its gap
      # (capped at MAX_GAP) whenever a request hits trouble (a Cloudflare
      # challenge or a Ferrum/socket error), so a struggling worker slows itself
      # without throttling the healthy ones.
      class Pacing
        def initialize(base: BASE_GAP, max: MAX_GAP)
          @base = base
          @max = max
          @gap = base
          @last = nil
        end

        attr_reader :gap

        # Sleep off whatever remains of this worker's gap since its last request,
        # then stamp the clock (in ensure, mirroring the old #time_req).
        def throttle
          sleep [@gap - (Time.now - @last), 0].max if @last
        ensure
          @last = Time.now
        end

        # Exponential backoff, capped at @max. Called before a retry on trouble.
        def backoff
          @gap = [@gap * 2, @max].min
        end
      end

      def index
        @index ||= Index.find_or_create :cie, file: "#{INDEXFILE}.yaml",
                                              pubid_class: ::Pubid::Cie::Identifier
      end

      # Parse a docidentifier string into a Pubid::Cie::Identifier, or nil if
      # pubid can't parse it or it won't survive the structured index — so a
      # single bad id never aborts the crawl or corrupts index-v2. The caller
      # (#write_file) records the skip.
      #
      # The guard mirrors the read side's acceptance test
      # (Index::FileIO#id_supported?, `from_hash(to_hash) == to_hash`): the
      # loader raises InvalidIndexError and rejects the WHOLE index on the first
      # id that doesn't round-trip, so an id that serializes but can't be
      # deserialized back must be dropped here rather than poison every lookup.
      def pubid(id)
        pid = ::Pubid::Cie.parse id
        hash = pid.to_hash
        return nil unless ::Pubid::Cie::Identifier.from_hash(hash).to_hash == hash

        pid
      rescue StandardError
        nil
      end

      def log_error(msg)
        Util.error msg
      end

      # @param hit [Nokogiri::HTML::Document]
      # @param doc [Mechanize::Page]
      # @return [Array<Relaton::Bib::Docidentifier>]
      def fetch_docid(hit, doc)
        code, code2 = parse_code hit, doc
        docid = []
        if code && !code.strip.empty?
          docid << Bib::Docidentifier.new(type: "CIE", content: code, primary: true)
          @errors[:docid_1] &&= false
        else
          @errors[:docid_1] &&= true
        end
        if code2 && !code2.strip.empty?
          type2 = code2.match(/\w+/).to_s
          docid << Relaton::Bib::Docidentifier.new(type: type2, content: code2.strip)
          @errors[:docid_2] &&= false
        else
          @errors[:docid_2] &&= true
        end
        isbn = doc.at('//h3[contains(.,"ISBN")]/following-sibling::span')&.text
        if isbn && !isbn.strip.empty?
          docid << Bib::Docidentifier.new(type: "ISBN", content: isbn)
          @errors[:docid_isbn] &&= false
        else
          @errors[:docid_isbn] &&= true
        end
        docid
      end

      def parse_code(hit, doc = nil)
        code = hit.at("h3/a").text.strip.squeeze(" ").sub(/\u25b9/, "").gsub(" / ", "/")
        c2idx = %r{(?:\(|/)(?<c2>(?:ISO|IEC)\s[^()]+)} =~ code
        code = code[0...c2idx].strip if c2idx
        [primary_code(code, doc), c2]
      end

      def primary_code(code, doc = nil)
        /^(?<code1>[^(]+)(?:\((?<code2>[a-zA-Z]+\d+,(?:\sPages)?[^)]+))?/ =~ code
        if code1&.match?(/^CIE/)
          parse_cie_code code1, code2, doc
        elsif (pcode = doc&.at('//h3[.="Product Code(s):"]/following-sibling::span'))
          "CIE #{pcode.text.strip.match(/[^,]+/)}"
        else
          num = code.match(/(?<=\()\w{2}\d+,.+(?=\))/).to_s.gsub(/,(?=\s)/, "").gsub(/,(?=\S)/, " ")
          "CIE #{num}"
        end
      end

      def parse_cie_code(code1, code2, doc = nil) # rubocop:disable Metrics/CyclomaticComplexity
        code = code1.size > 25 && code2 ? "CIE #{code2.sub(/,(\sPages)?/, '')}" : code1
        add = doc&.at("//hgroup/h2")&.text&.match(/(Add)endum\s(\d+)$/)
        return code unless add

        "#{code} #{add[1]} #{add[2]}"
      end

      def fetch_docnumber(hit)
        parse_code(hit).first.sub(/^CIE\s(?:ISO\s)?/, "")
      end

      # @param doc [Mechanize::Page]
      # @return [Array<Relaton::Bib::Title>]
      def fetch_title(doc)
        t = doc.at("//hgroup/h2/text()", "//hgroup/h1/text()")
        unless t && !t.text.strip.empty?
          @errors[:title] &&= true
          return []
        end

        result = Bib::Title.from_string t.text.strip
        @errors[:title] &&= result.empty?
        result
      end

      # @param doc [Mechanize::Page]
      # @return [Array<Relaton::Bib::Date>]
      def fetch_date(doc)
        result = doc.xpath("//h3[.='Published:']/following-sibling::span").map do |d|
          pd = d.text.strip
          on = pd.match?(/^\d{4}(?:[^-]|$)/) ? pd : Date.strptime(pd, "%m/%d/%Y").strftime("%Y-%m-%d")
          Bib::Date.new(type: "published", at: on)
        end
        @errors[:date] &&= result.empty?
        result
      end

      # @param doc [Mechanize::Page]
      # @return [String]
      def fetch_edition(doc)
        ed = doc.at("//h3[.='Edition:']/following-sibling::span")
        @errors[:edition] &&= true
        return unless ed

        content = ed.text.slice(/^\d+(?=(st|nd|rd|th))/)
        if content
          @errors[:edition] = false
          Bib::Edition.new(content: content)
        end
      end

      # @param doc [Mechanize::Page]
      # @return [Array<Relaton::Cie::Relation>]
      def fetch_relation(doc) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        rels = doc.xpath('//section[@class="history"]/ol/li[not(contains(@class,"selected-product"))]').map do |rel|
          ref = rel.at("a")
          url = "https://www.techstreet.com#{ref[:href]}"
          title = Bib::Title.from_string ref.at('p/span[@class="title"]').text
          did = ref.at("h3").text
          docid = [Bib::Docidentifier.new(type: "CIE", content: did, primary: true)]
          on = ref.at("p/time")
          date = [Bib::Date.new(type: "published", at: on[:datetime])]
          source = [Bib::Uri.new(type: "src", content: url)]
          bibitem = ItemData.new docidentifier: docid, title: title, source: source, date: date
          type = ref.at('//li/i[contains(@class,"historical")]') ? "updates" : "updatedBy"
          Bib::Relation.new(type: type, bibitem: bibitem)
        end
        @errors[:relation] &&= rels.empty?
        rels
      end

      # @param url [String]
      # @return [Array<Relaton::Bib::Uri>]
      def fetch_source(url)
        @errors[:source] &&= url.nil? || url.empty?
        return [] if url.nil? || url.empty?

        [Bib::Uri.new(type: "src", content: url)]
      end

      # @param doc [Mechanize::Page]
      # @return [Array<Relaton::Bib::LocalizedMarkedUpString>]
      def fetch_abstract(doc)
        content = doc.at('//div[contains(@class,"description")]')&.text&.strip
        if content.nil? || content.empty?
          @errors[:abstract] &&= true
          return []
        end

        result = [Bib::Abstract.new(content: content, language: "en", script: "Latn")]
        @errors[:abstract] &&= result.empty?
        result
      end

      # @param doc [Mechanize::Page]
      # @return [Array<Relaton::Bib::Contributor>]
      def fetch_contributor(doc) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity
        authors = doc.xpath('//hgroup/p[not(@class="pub_date")]').text.gsub "\"", ""
        contribs = []
        until authors.empty?
          /^(?<sname1>\S+(?:\sder?\s)?[^\s,]+)
          (?:,?\s(?<sname2>[\w-]{2,})(?=,\s+\w\.))?
          (?:,?\s(?<fname>W-T\.[\w-]{2,})(?!,\s+\w\.))?
          (?:(?:\s?,\s?|\s)(?<init>(?:\w(?:\s?\.|\s|,|$)[\s-]?)+))?
          (?:(?:[,;]\s*|\s+|\.|(?<=\s))(?:and\s)?)?/x =~ authors
          raise StandardError, "Author name not found in \"#{authors}\"" unless $LAST_MATCH_INFO

          authors.sub! $LAST_MATCH_INFO.to_s, ""
          sname = [sname1, sname2].compact.join " "
          surname = Bib::LocalizedString.new content: sname, language: "en", script: "Latn"
          forename = []
          forename << Bib::FullNameType::Forename.new(content: fname, language: "en", script: "Latn") if fname
          (init&.strip || "").split(/(?:,|\.)(?:-|\s)?/).each do |int|
            forename << Bib::FullNameType::Forename.new(content: "", initial: int.strip, language: "en", script: "Latn")
          end
          fullname = Bib::FullName.new surname: surname, forename: forename
          person = Bib::Person.new name: fullname
          role = Bib::Contributor::Role.new type: "author"
          contribs << Bib::Contributor.new(person: person, role: [role])
          @errors[:contributor_author] &&= contribs.empty?
        end
        org_name = Bib::TypedLocalizedString.new(content: "Commission Internationale de L'Eclairage")
        abbrev = Bib::LocalizedString.new content: "CIE"
        org_uri = Bib::Uri.new content: "cie.co.at"
        org = Bib::Organization.new(name: [org_name], abbreviation: abbrev, uri: [org_uri])
        org_role = Bib::Contributor::Role.new type: "publisher"
        contribs << Bib::Contributor.new(organization: org, role: [org_role])
      end

      def fetch_ext
        Ext.new(doctype: fetch_doctype, flavor: "cie")
      end

      def fetch_doctype
        Bib::Doctype.new(content: "document")
      end

      # @param bib [RelatonCie::BibliographicItem]
      # @param pos [Integer, nil] the hit's catalogue position, used only by the
      #   parallel pool to keep a deterministic last-by-position winner when two
      #   hits map to the same output file. nil (direct calls) keeps the
      #   historical warn-and-overwrite behavior.
      def write_file(bib, pos = nil) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        id = bib.docidentifier[0].content
        file = output_file id
        # Index every distinct id (the serial crawl indexes each one, even two
        # that resolve to the same file), before the content-dedup gate below.
        pid = pubid id
        if pid
          index.add_or_update pid, file
        else
          Util.warn { "Unparseable id `#{id}` was not indexed (#{file})" }
        end
        # Only the last-by-position hit writes the shared file's content.
        return if superseded? file, pos

        if @files.include? file
          Util.warn do
            "File #{file} exists. Docid: #{bib.docidentifier[0].content}\n" \
            "Link: #{bib.source.detect { |l| l.type == 'src' }.content}"
          end
        else @files << file
        end
        File.write file, serialize(bib), encoding: "UTF-8"
      end

      # True when another hit with a *later* catalogue position has already
      # claimed `file`. The serial crawl is last-writer-wins, so that later hit
      # is canonical and this (earlier or duplicate) content write must be
      # dropped — making the output independent of worker completion order. With
      # pos nil there's no position to compare, so nothing is superseded.
      def superseded?(file, pos)
        return false if pos.nil?

        prev = @seen[file]
        return true if prev && prev >= pos

        @seen[file] = pos
        false
      end

      def to_xml(bib) = bib.to_xml(bibdata: true)
      def to_yaml(bib) = bib.to_yaml
      def to_bibxml(bib) = bib.to_rfcxml

      # Fetch and store one document. The slow detail-page load
      # (`worker_agent.get`, throttled by this worker's `pacing`) runs outside
      # the lock — that's the parallel win; the cheap build + write is done under
      # @mutex so @files/@errors/@seen and the index stay consistent across
      # workers. Called directly (single stubbed agent) by specs and from the
      # pool with a per-worker agent/pacing/position.
      #
      # @param hit [Nokogiri::HTML::Element]
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def parse_page(hit, pos = nil, worker_agent = agent, pacing = nil)
        url = hit.at('h3/a')[:href]
        doc = time_req(pacing) { worker_agent.get url }
        @mutex.synchronize do
          item = ItemData.new(
            type: "standard", source: fetch_source(url), docnumber: fetch_docnumber(hit),
            docidentifier: fetch_docid(hit, doc), title: fetch_title(doc),
            abstract: fetch_abstract(doc), date: fetch_date(doc),
            edition: fetch_edition(doc), contributor: fetch_contributor(doc),
            relation: fetch_relation(doc), language: "en", script: "Latn",
            ext: fetch_ext
          )
          write_file item, pos
        end
      rescue StandardError => e
        Util.error do
          "Document: #{url}\n#{e.message}\n#{e.backtrace}"
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def fetch(_source = nil)
        process_hits collect_hits
        index.save
        report_errors
      ensure
        @agent&.quit
      end

      # Phase 1 (serial): walk the search-result pages, following the "next"
      # link, and collect every //li[@data-product] hit into one list (~12 page
      # loads at per_page=100, so serial pacing here is cheap). The detail-page
      # fetches happen in #process_hits.
      def collect_hits(url = URL, hits = [])
        result = time_req(listing_pacing) { agent.get url }
        hits.concat result.xpath("//li[@data-product]").to_a
        np = result.at '//a[@class="next_page"]'
        return hits unless np

        next_href = np[:href]
        next_url = next_href.start_with?("http") ? next_href : "https://www.techstreet.com#{next_href}"
        collect_hits next_url, hits
      end

      # Phase 2 (parallel): fan the collected hits out across a bounded worker
      # pool. Each worker owns its own stealth browser agent and its own adaptive
      # pacing. The agents are built up front on this thread so a Chrome-launch
      # failure aborts fast (before any hit is enqueued and before the index is
      # saved) rather than leaving a dead worker that can't drain the queue; and
      # every created agent is quit in the ensure even if enqueuing or a worker
      # raises. Hits carry their catalogue position so #write_file keeps a
      # deterministic winner for any duplicate output file — byte-identical
      # output regardless of completion order.
      def process_hits(hits)
        return if hits.empty?

        n = self.class.concurrency
        agents = []
        queue = SizedQueue.new(n * 2)
        n.times { agents << build_agent }
        workers = agents.map { |worker_agent| spawn_worker(queue, worker_agent) }
        hits.each_with_index { |hit, pos| queue << [hit, pos] }
        n.times { queue << nil } # poison pills
        workers.each(&:join)
      ensure
        agents&.each(&:quit)
      end

      # One pool worker: drains the queue with its own browser agent + pacing
      # until the poison pill (nil). parse_page swallows per-document errors, so
      # the thread runs to the pill; the agent is quit by #process_hits.
      def spawn_worker(queue, worker_agent)
        pacing = Pacing.new
        Thread.new do
          while (item = queue.pop)
            hit, pos = item
            parse_page hit, pos, worker_agent, pacing
          end
        end
      end

      # Pacing for the serial listing phase (Phase 1). Also the fallback pacing
      # for #time_req when no per-worker pacing is passed (direct calls / specs).
      def listing_pacing
        @listing_pacing ||= Pacing.new
      end

      RETRIABLE_ERRORS = [
        SocketError,
        Ferrum::TimeoutError,
        Ferrum::PendingConnectionsError,
        Ferrum::StatusError,
        BrowserAgent::ChallengeError
      ].freeze

      # Run a throttled request through the given worker's pacing, retrying up to
      # 4 times on a retriable error (challenge / Ferrum / socket) and backing
      # that worker's gap off before each retry.
      def time_req(pacing = listing_pacing)
        pacing ||= listing_pacing
        tries = 0
        begin
          tries += 1
          pacing.throttle
          yield
        rescue *RETRIABLE_ERRORS => e
          pacing.backoff
          retry if tries < 4
          raise e
        end
      end
    end
  end
end
