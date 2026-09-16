# encoding: UTF-8
# frozen_string_literal: true

require "yaml"
require "gb_agencies"

module Relaton
  module Gb
    # Common scrapping methods.
    module Scraper
      STAGES = { "即将实施" => "published",
                "现行" => "activated",
                "废止" => "obsoleted",
                "被代替" => "replaced" }.freeze

      @prefixes = nil

      # @param doc [Moxml::Document]
      # @param src [String]
      # @param hit [RelatonGb::Hit]
      # @return [Hash]
      def scrapped_data(doc, src, hit) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        {
          fetched: Date.today.to_s,
          type: "standard",
          docidentifier: get_docid(hit.docref),
          title: get_titles(doc),
          contributor: get_contributors(doc, hit.docref),
          status: get_status(doc, hit.status),
          source: get_source(src),
          date: get_dates(doc),
          language: ["zh"],
          script: ["Hans"],
          ext: get_ext(doc, hit.docref),
        }
      end

      # @param docref [String]
      # @return [Array<Relaton::Bib::Docidentifier>]
      def get_docid(docref)
        [Docidentifier.new(content: docref, type: "Chinese Standard", primary: true)]
      end

      # @param doc [Moxml::Document]
      # @param docref [Strings]
      # @return [Array<Relaton::Bib::Contributor>]
      def get_contributors(doc, docref)
        name = docref_pubid(docref)&.publisher&.to_s
        gbtype = get_gbtype(doc, docref)
        org_names = %w[en zh].map { |l| create_org_name(l, name, gbtype) }.compact
        return [] unless org_names.any?

        org = Bib::Organization.new name: org_names
        role = Bib::Contributor::Role.new type: "publisher"
        [Bib::Contributor.new(organization: org, role: [role])]
      end

      # @param lang [String]
      # @param name [String]
      # @param gbtype [Hash]
      # @return [Relaton::Bib::TypedLocalizedString, nil]
      def create_org_name(lang, name, gbtype)
        ag = GbAgencies::Agencies.new(lang, {}, "")
        content = ag.standard_agency1(gbtype.scope, name, gbtype.mandate)
        return unless content

        Bib::TypedLocalizedString.new language: lang, content: content
      end

      # @param doc [Moxml::Document]
      # @return [Array<Relaton::Bib::Title>]
      def get_titles(doc)
        tzh = doc.at("//td[contains(text(), '中文标准名称')]/b").text
        titles = Relaton::Bib::Title.from_string tzh, "zh", "Hans"
        ten = doc.at("//td[contains(text(), '英文标准名称')]").text.match(/[\w\s]+/).to_s
        return titles if ten.empty?

        titles + Relaton::Bib::Title.from_string(ten, "en", "Latn")
      end

      # @param doc [Moxml::Document]
      # @param status [String, NilClass]
      # @return [Relaton::Bib::Status]
      def get_status(doc, status = nil)
        status ||= doc.at("//td[contains(., '标准状态')]/span")&.text&.strip
        return unless STAGES[status]

        stage = Bib::Status::Stage.new content: STAGES[status]
        Bib::Status.new stage: stage
      end

      private

      # @param doc [Moxml::Document]
      # @return [Array<String>]
      def get_ccs(doc)
        code = doc.at("//div[contains(text(), '中国标准分类号')]/following-sibling::div").text.strip
        [CCS.new(code: code)]
      end

      # @param doc [Moxml::Document]
      # @return [Array<Relaton::Bib::ICS>]
      def get_ics(doc)
        ics = doc.at("//div[contains(text(), '国际标准分类号')]/following-sibling::div"\
                    " | //dt[contains(text(), '国际标准分类号')]/following-sibling::dd")
        return [] unless ics

        code = ics.text.strip
        [Bib::ICS.new(code: code)]
      end

      # @param doc [Moxml::Document]
      # @return [String]
      def get_scope(doc)
        issued = doc.at("//div[contains(., '发布单位')]/following-sibling::div")
        case issued&.text
        when /国家标准/ then "national"
        when /^行业标准/ then "sector"
        end
      end

      # The publisher of a social group standard names the group
      # (`T/GZAEPI`), so only its first segment keys `yaml/prefixes.yaml`.
      #
      # @param ref [String]
      # @return [Hash{String=>String}, nil]
      def get_prefix(ref)
        pref = docref_pubid(ref)&.publisher&.to_s
        prefix pref.split("/").first if pref
      end

      # @param pref [String]
      # @return [Hash{String=>String}]
      def prefix(pref)
        @prefixes ||= YAML.load_file File.join(__dir__, "yaml/prefixes.yaml")
        @prefixes[pref]
      end

      # @param ref [String]
      # @return [String]
      def get_mandate(ref)
        case docref_pubid(ref)&.mandate
        when "T" then "recommended"
        when "Z" then "guidelines"
        else "mandatory"
        end
      end

      def get_source(src)
        (Bib::Uri.new(type: "src", content: src))
      end

      # @param doc [Moxml::Document]
      # @return [Array<Hash>]
      #   * :type [String] type of date
      #   * :on [String] date
      def get_dates(doc)
        date = doc.at("//div[contains(text(), '发布日期')]/following-sibling::div"\
                      " | //dt[contains(text(), '发布日期')]/following-sibling::dd")
        [Bib::Date.new(type: "published", at: date.text.delete("\r\n\t\t"))]
      end

      def get_ext(doc, docref)
        Ext.new(
          doctype: get_type,
          gbtype: get_gbtype(doc, docref),
          flavor: "gb",
          # gbcommittee: get_committee(doc, docref),
          ccs: get_ccs(doc),
          ics: get_ics(doc),
          structuredidentifier: fetch_structuredidentifier(docref),
          plannumber: parse_docref(docref)[0],
        )
      end

      def get_type
        Doctype.new content: "standard"
      end

      # @param doc [Moxml::Document]
      # @param ref [String]
      # @return [Relaton::Gb::GbType]
      def get_gbtype(doc, ref)
        # ref = get_ref(doc)
        GbType.new(scope: get_scope(doc), prefix: get_prefix(ref)&.fetch("prefix", nil), mandate: get_mandate(ref), topic: "other")
      end

      # A portal docref is data, so a value pubid cannot read is nil rather
      # than an error.
      #
      # @param docref [String]
      # @return [Pubid::Gb::Identifier, nil]
      def docref_pubid(docref)
        require "pubid"
        ::Pubid::Gb::Identifier.parse(docref)
      rescue StandardError
        nil
      end

      # @param docref [String]
      # @return [Array<String, nil>] the id without part and year (e.g.
      #   `GB/T 5606`), the part, and the year
      def parse_docref(docref)
        pubid = docref_pubid(docref)
        return [docref, nil, nil] unless pubid

        [pubid.exclude(:part, :year).to_s, pubid.part, pubid.year]
      end

      # @param docref [String]
      # @return [Relaton::Iso::StructuredIdentifier]
      def fetch_structuredidentifier(docref)
        docnumber, partnumber, origyr = parse_docref(docref)
        project_number = ProjectNumber.new(part: partnumber, origyr: origyr, content: docref)
        StructuredIdentifier.new(
          type: "Chinese Standard", tc_document_number: docnumber, project_number: project_number,
        )
      end
    end
  end
end
