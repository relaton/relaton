require "cgi"
require "ieee-idams"

module Relaton
  module Ieee
    class IdamsParser
      include Core::ArrayWrapper

      ATTRS = %i[
        docnumber title date docidentifier contributor abstract copyright status
        relation source keyword ext
      ].freeze

      # Upstream IDAMS abstracts sometimes carry escaped ASCII control
      # characters as printable tokens like `<<ETX>>`. They are meaningless
      # in output, and `<<…>>` blows up XML serialization downstream
      # (libxml2 reads `<<` as the start of a tag). Strip the whole family.
      CONTROL_PLACEHOLDER_RE = /<<[A-Z]{2,5}>>/.freeze

      def initialize(doc, fetcher, errors = {})
        @doc = doc
        @fetcher = fetcher
        @errors = errors
      end

      #
      # Parse IEEE document
      #
      # @return [Relaton::Ieee::ItemData] bibliographic item data
      #
      def parse
        args = { type: "standard", language: ["en"], script: ["Latn"] }
        ATTRS.each { |attr| args[attr] = send("parse_#{attr}") }
        ItemData.new(**args)
      end

      def parse_docnumber
        result = docnumber
        @errors[:docnumber] &&= result.nil?
        result
      end

      #
      # Parse docnumber
      #
      # @return [String] PubID
      #
      def docnumber
        @docnumber ||= pubid&.to_id
      end

      #
      # Create PubID
      #
      # @return [Relaton::Ieee::RawbibIdParser] PubID
      #
      def pubid
        @pubid ||= begin
          normtitle = @doc.normtitle
          stdnumber = @doc.publicationinfo.stdnumber
          RawbibIdParser.parse(normtitle, stdnumber)
        end
      end

      #
      # Parse title
      #
      # @return [Array<Relaton::Bib::Title>]
      #
      def parse_title
        result = @doc.btitle.map { |args| Bib::Title.new(**args) }
        @errors[:title] &&= result.empty?
        result
      end

      #
      # Parse date
      #
      # @return [Array<Relaton::Bib::Date>]
      #
      def parse_date
        result = @doc.bdate.map { |args| Bib::Date.new(type: args[:type], at: args[:on]) }
        @errors[:date] &&= result.empty?
        result
      end

      #
      # Parse identifiers
      #
      # @return [Array<Relaton::Bib::Docidentifier>]
      #
      def parse_docidentifier # rubocop:disable Metrics/MethodLength
        ids = @doc.isbn_doi.map { |id| id[:content] = id.delete(:id); id }

        ids.unshift(content: pubid.to_s(trademark: true), scope: "trademark", type: "IEEE", primary: true)
        ids.unshift(content: pubid.to_s, type: "IEEE", primary: true)

        result = ids.map { |dcid| Bib::Docidentifier.new(**dcid) }
        @errors[:docidentifier] &&= result.empty?
        result
      end

      #
      # Parse contributors
      #
      # @return [Array<Relaton::Bib::Contributor>]
      #
      def parse_contributor
        contributors = []

        # Add publisher contributor
        name, addr = @doc.contrib_name_addr { |args| Relaton::Bib::Address.new(**args) }
        org = create_org name, addr
        role = Bib::Contributor::Role.new type: "publisher"
        contributors << Relaton::Bib::Contributor.new(organization: org, role: [role])

        # Add committee contributors from editorial group
        result = contributors + parse_committee_contributors
        @errors[:contributor] &&= result.empty?
        result
      end

      #
      # Parse committee contributors from editorial group
      #
      # @return [Array<Relaton::Bib::Contributor>]
      #
      def parse_committee_contributors
        committees = @doc.editorialgroup
        return [] unless committees

        result = committees.map do |committee|
          create_committee_contributor(committee)
        end
        @errors[:committee] &&= result.empty?
        result
      end

      #
      # Create a committee contributor
      #
      # @param [String] committee committee name
      #
      # @return [Relaton::Bib::Contributor]
      #
      def create_committee_contributor(committee)
        desc = Bib::LocalizedMarkedUpString.new(content: "committee", language: "en", script: "Latn")
        role = Bib::Contributor::Role.new(type: "author", description: [desc])

        # Create IEEE organization with committee as subdivision
        orgname = Bib::TypedLocalizedString.new(
          content: "Institute of Electrical and Electronics Engineers", language: "en", script: "Latn"
        )
        abbr = Bib::LocalizedString.new(content: "IEEE")

        # Create subdivision for the committee
        subdiv_name = Bib::TypedLocalizedString.new(content: CGI.unescapeHTML(committee), language: "en", script: "Latn")
        subdivision = Bib::Subdivision.new(type: "committee", name: [subdiv_name])

        org = Bib::Organization.new(name: [orgname], abbreviation: abbr, subdivision: [subdivision])
        Relaton::Bib::Contributor.new(organization: org, role: [role])
      end

      #
      # Parse abstract
      #
      # @return [Array<Relaton::Bib::LocalizedMarkedUpString>]
      #
      def parse_abstract
        result = @doc.volume.article.articleinfo.abstract.each_with_object([]) do |abs, acc|
          next unless abs.abstract_type == "Standard"

          content = abs.value.gsub(CONTROL_PLACEHOLDER_RE, "").strip
          next if content.empty?

          acc << Bib::Abstract.new(content: content, language: "en", script: "Latn")
        end
        @errors[:abstract] &&= result.empty?
        result
      end

      #
      # Parse copyright
      #
      # @return [Array<Relaton::Bib::Copyright>]
      #
      def parse_copyright
        result = @doc.copyright.map do |owner, year|
          contrib = owner.map { |own| Bib::ContributionInfo.new organization: create_org(own) }
          Bib::Copyright.new(owner: contrib, from: year)
        end
        @errors[:copyright] &&= result.empty?
        result
      end

      #
      # Parse status
      #
      # @return [Relaton::Bib::Status, nil]
      #
      def parse_status
        return if @doc.docstatus.nil? || @doc.docstatus.empty?

        @errors[:status] &&= @doc.docstatus[:stage].nil?
        stage = Bib::Status::Stage.new content: @doc.docstatus[:stage]
        Bib::Status.new stage: stage
      end

      #
      # Parse relation
      #
      # @return [Array<Relaton::Bib::Relation>]
      #
      def parse_relation # rubocop:disable Metrics/AbcSize
        result = array(@doc.publicationinfo.standard_relationship).each_with_object([]) do |relation, acc|
          if (ref = @fetcher.backrefs[relation.date_string])
            rel = @fetcher.create_relation(relation.type, ref)
            acc << rel if rel
          elsif !relation.date_string.include?("Inactive Date") && docnumber
            @fetcher.add_crossref(docnumber, relation)
          end
        end
        @errors[:relation] &&= result.empty?
        result
      end

      #
      # Parce source link
      #
      # @return [Array<Relaton::Bib::Uri>]
      #
      def parse_source
        result = @doc.link { |url| Bib::Uri.new(content: url, type: "src") }
        @errors[:source] &&= result.empty?
        result
      end

      #
      # Parse keyword
      #
      # @return [Array<Strign>]
      #
      def parse_keyword
        result = @doc.keyword.map do |kw|
          Bib::Keyword.new(vocab: Bib::LocalizedString.new(content: CGI.unescapeHTML(kw), language: "en", script: "Latn"))
        end
        @errors[:keyword] &&= result.empty?
        result
      end

      private

      #
      # Create organization
      #
      # @param [String] name organization's name
      # @param [Array<Hash>] addr address
      #
      # @return [Relaton::Bib::Organization]
      def create_org(name, addr = []) # rubocop:disable Metrics/MethodLength
        case name
        when "IEEE"
          abbr = Bib::LocalizedString.new content: name
          n = "Institute of Electrical and Electronics Engineers"
          uri = Bib::Uri.new content: "http://www.ieee.org", type: "org"
        when "ANSI"
          abbr = Bib::LocalizedString.new content: name
          n = "American National Standards Institute"
          uri = Bib::Uri.new content: "https://www.ansi.org", type: "org"
        else n = name
        end
        orgname = Bib::TypedLocalizedString.new(content: n, language: "en", script: "Latn")
        Bib::Organization.new(name: [orgname], abbreviation: abbr, uri: [uri], address: create_address(addr))
      end

      def create_address(addr)
        addr.map { |ad| Bib::Address.new(**ad) }
      end

      def parse_ext
        standard_status = @doc.publicationinfo.standard_status
        standard_modified = @doc.standard_modifier
        pubstatus = @doc.publicationinfo.pubstatus
        holdstatus = @doc.publicationinfo.holdstatus
        @errors[:standard_status] &&= standard_status.nil?
        @errors[:standard_modified] &&= standard_modified.nil?
        @errors[:pubstatus] &&= pubstatus.nil?
        @errors[:holdstatus] &&= holdstatus.nil?
        Ext.new(
          doctype: parse_doctype,
          flavor: "ieee",
          ics: parse_ics,
          standard_status: standard_status,
          standard_modified: standard_modified,
          pubstatus: pubstatus,
          holdstatus: holdstatus,
        )
      end

      #
      # Parse doctype
      #
      # @return [Relaton::Ieee::Doctype] doctype
      #
      def parse_doctype
        Doctype.new content: @doc.doctype
      end

      #
      # Parse ICS
      #
      # @return [Array<Relaton::Bib::ICS>]
      #
      def parse_ics
        result = @doc.ics.each_with_object([]) do |ics, acc|
          acc << Bib::ICS.new(**ics) if ics[:code] && !ics[:code].empty?
        end
        @errors[:ics] &&= result.empty?
        result
      end
    end
  end
end
