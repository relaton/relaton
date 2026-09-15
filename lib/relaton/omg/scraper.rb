# frozen_string_literal: true

require "json"
require "mechanize"
require "pubid"

module Relaton
  module Omg
    class Scraper
      URL_PATTERN = "https://www.omg.org/spec/"
      LD_DATE = "https://www.omg.org/techprocess/ab/SpecificationMetadata/publicationDate"

      # @param acronym [String] the specification acronym, e.g. "UML"
      # @param version [String, nil] the version, e.g. "2.1.1" or "2.5 beta 1"
      # @param part [String, nil] the document part, e.g. "Superstructure"
      def initialize(acronym, version = nil, part = nil)
        @acronym = acronym
        @version = version
        @part = part
      end

      # @param ref [String] the OMG reference, e.g. "OMG UML 2.1.1 Superstructure"
      # @return [Relaton::Omg::ItemData, nil] nil when the page is not found
      # @raise [Pubid::Errors::ParseError] when the reference is not an OMG
      #   identifier
      def self.scrape_page(ref)
        pubid = ::Pubid::Omg::Identifier.parse(ref)
        scraper = new(pubid.acronym, pubid.version, pubid.part)
        doc = scraper.get_doc
        return if doc.nil? || scraper.fetch_link.empty?

        Omg::ItemData.new(**scraper.item)
      end

      def get_doc
        @url = "#{URL_PATTERN}#{@acronym}/"
        @url += @version.gsub(" ", "/") if @version
        agent = Mechanize.new
        agent.open_timeout = 10
        @doc = agent.get(@url)
      rescue Mechanize::ResponseCodeError => e
        return if e.response_code == "404"

        raise Relaton::RequestError, "Unable acces #{@url} (#{e.response_code})"
      rescue Net::OpenTimeout
        raise Relaton::RequestError, "Unable acces #{@url} (timeout)"
      end

      def item
        {
          fetched: ::Date.today.to_s,
          docidentifier: fetch_docid,
          title: fetch_title,
          abstract: fetch_abstract,
          version: fetch_version,
          date: fetch_date,
          status: fetch_status,
          source: fetch_link,
          relation: fetch_relation,
          keyword: fetch_keyword,
          license: fetch_license,
        }
      end

      def fetch_title
        content = @doc.at('//dt[.="Title:"]/following-sibling::dd').text
        content += ": #{@part}" if @part
        [Bib::Title.new(type: "main", content: content, language: "en", script: "Latn")]
      end

      # The version comes from the page, not from the query, so a versionless
      # query (`OMG AMI4CCM`) answers with the version that the page shows.
      def fetch_docid
        id = render_id(@acronym, doc_version, @part)
        [Docidentifier.new(content: id, type: "OMG", primary: true)]
      end

      def fetch_abstract
        content = @doc.at('//section[@id="document-metadata"]/div/div/p').text
        [Bib::Abstract.new(content: content, language: "en", script: "Latn")]
      end

      def fetch_version
        [Bib::Version.new(revision_date: pub_date, draft: doc_version)]
      end

      def doc_version
        @doc_version ||= @doc.at('//dt[.="Version:"]/following-sibling::dd/p/span').text
      end

      def fetch_date
        return [] unless pub_date

        [Bib::Date.new(type: "published", at: pub_date.to_s)]
      end

      def pub_date
        return @pub_date if defined? @pub_date

        @pub_date = jsonld_date || dd_date
      end

      # The visible date renders the month name in the locale of the server, and
      # the CDN caches that variant. Parse the machine-readable value first.
      #
      # @return [Date, nil]
      def jsonld_date
        script = @doc.at('//script[@type="application/ld+json"]')
        return unless script

        node = JSON.parse(script.text).find { |e| e.is_a?(Hash) && e[LD_DATE] }
        value = node && node[LD_DATE].first["@value"]
        value && ::Date.parse(value)
      rescue JSON::ParserError, ::Date::Error
        nil
      end

      # @return [Date, nil]
      def dd_date
        text = @doc.at('//dt[.="Publication Date:"]/following-sibling::dd').text.strip
        ::Date.parse text
      rescue ::Date::Error
        Util.warn "Cannot parse the publication date `#{text}`."
        nil
      end

      def fetch_status
        status = @doc.at('//dt[.="Document Status:"]/following-sibling::dd')
        stage = status.text.strip.match(/\w+/).to_s
        Bib::Status.new(stage: Bib::Status::Stage.new(content: stage))
      end

      def fetch_link
        return @links if @links

        @links = []
        if @part
          a = @doc.at("//a[@href='#{@url}/#{@part}/PDF']")
          @links << Bib::Uri.new(type: "src", content: a[:href]) if a
        else
          a = @doc.at('//dt[.="This Document:"]/following-sibling::dd/a')
          @links << Bib::Uri.new(type: "src", content: a[:href]) if a
          pdf = @doc.at('//a[@class="download-document"]')
          @links << Bib::Uri.new(type: "pdf", content: pdf[:href]) if pdf
        end
        @links
      end

      def fetch_relation
        v = @doc.xpath('//h2[.="History"]/following-sibling::section/div/table/tbody/tr')
        v.reduce([]) do |mem, row|
          ver = row.at("td").text
          unless ver == doc_version
            acronym = row.at("td[3]/a")[:href].split("/")[4]
            id = render_id(acronym, ver)
            docid = Docidentifier.new(content: id, type: "OMG")
            bibitem = Bib::ItemBase.new(formattedref: Bib::Formattedref.new(content: id), docidentifier: [docid])
            mem << Bib::Relation.new(type: "obsoletes", bibitem: bibitem)
          end
          mem
        end
      end

      def fetch_keyword
        @doc.xpath('//dt[.="Categories:"]/following-sibling::dd/ul/li/a/em').map do |kw|
          Bib::Keyword.new(vocab: Bib::LocalizedString.new(content: kw.text))
        end
      end

      def fetch_license
        @doc.xpath(
          '//dt/span/a[contains(., "IPR Mode")]/../../following-sibling::dd/span',
        ).map { |l| l.text.match(/[\w\s-]+/).to_s.strip }
      end

      private

      # @return [String] the identifier, rendered by pubid
      def render_id(acronym, version, part = nil)
        ::Pubid::Omg::Identifiers::Specification.new(
          acronym: acronym, version: version, part: part,
        ).to_s
      end
    end
  end
end
