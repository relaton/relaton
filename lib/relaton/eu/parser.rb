module Relaton
  module Eu
    #
    # Map one CELLAR result row (`Cellar::QUERY`) to a generic Bib::ItemData.
    #
    # The act identifier comes from the ELI, never from the CELEX number:
    # CELEX numbers are CELLAR's own sequence, and they differ from the act
    # number for many decisions (ECB decision 2016/245 is CELEX 32016D0002).
    #
    class Parser
      # A work of an act this flavor covers, in its original version. The
      # ELI type segment can carry a subtype (`reg_impl`, `dec_del`, …):
      # implementing and delegated acts are numbered with their act type,
      # and `Pubid::Eu` reads only the bare type, so the subtype is dropped
      # for the parse. A corrigendum (`…/corrigendum/<date>/oj`), and every
      # other ELI type (`C`, `convention`, …), does not match.
      ELI = %r{\Ahttp://data\.europa\.eu/eli/(reg|dir|dec)(?:_[a-z]+)?/(\d{4})/(\d+)/oj\z}

      # The act citation in an Official Journal title:
      # `Regulation (EU) No 1227/2011`, `Directive 93/42/EEC`,
      # `Decision (EU) 2016/245`. Only the pair of numbers is read.
      CITATION = %r{\b(Regulation|Directive|Decision)\b[^\d]{0,40}?(\d+)/(\d+)}

      # The note that closes many titles; it is not part of the title.
      EEA_NOTE = /\s*\(?\s*Text with EEA relevance\s*\)?\.?\s*\z/i

      # A placeholder CELLAR uses for an unknown entry-into-force date.
      PLACEHOLDER_DATE = /\A1001-/

      PUBLISHER = %w[OP Publications\ Office\ of\ the\ European\ Union].freeze

      EURLEX = "https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:".freeze

      #
      # @param binding [Hash{String=>Hash}] one SPARQL result row
      # @return [Bib::ItemData, nil] nil for a work the flavor does not cover
      #
      def self.parse(binding)
        new(binding).parse
      end

      def initialize(binding)
        @row = binding.transform_values { |v| v["value"].to_s.strip }
                      .reject { |_, v| v.empty? }
        # The Official Journal writes a no-break space after `No`
        # (`No 1227/2011`); a title keeps plain spaces.
        @row["title"] &&= @row["title"].gsub(/[[:space:]]+/, " ").strip
      end

      # @return [Bib::ItemData, nil]
      def parse
        return unless pubid

        Bib::ItemData.new(
          id: pubid.to_s.gsub(/\W/, ""), type: "standard", title: title,
          docidentifier: docidentifier, date: date, contributor: contributor,
          status: status, relation: relation, source: source,
          language: ["en"], script: ["Latn"], ext: ext
        )
      end

      #
      # The act identifier, from the ELI, in the order the act's own title
      # prints it.
      #
      # @return [Pubid::Eu::Identifier, nil] nil when the work has no ELI of
      #   an act this flavor covers, or pubid cannot read it
      #
      def pubid
        return @pubid if defined? @pubid

        @pubid = parse_eli
      end

      # @return [String, nil] why a work of a covered act was not read: an
      #   ELI that matches `ELI` but pubid cannot read. Nil for a work the
      #   flavor does not cover, which is skipped and not an error.
      def error
        pubid
        @error
      end

      private

      def parse_eli
        m = ELI.match(@row["eli"]) or return
        id = ::Pubid::Eu.parse("http://data.europa.eu/eli/#{m[1]}/#{m[2]}/#{m[3]}/oj")
        keep_title_order id
      rescue ::Pubid::Errors::Error, ArgumentError => e
        @error = "CELEX #{@row['celex']}: pubid cannot read ELI " \
                 "`#{@row['eli']}` (#{e.message})"
        nil
      end

      #
      # Before 2015 a decision or a directive can print `<number>/<year>`
      # (`Decision No 1082/2013/EU`) or `<year>/<number>`
      # (`Decision 2010/87/EU`), and only its title tells. A pair that does
      # not name this act (the title cites another act first), or that reads
      # the same both ways (`2003/2003`), changes nothing.
      #
      def keep_title_order(id)
        number_first = title_order(id)
        unless number_first.nil? || number_first == id.default_number_first?
          id.number_first = number_first
        end
        id
      end

      def title_order(id)
        type = id.class.name.split("::").last
        year = id.year.to_s
        years = [year, year[2..]]
        @row["title"].to_s.scan(CITATION) do |act, first, second|
          next unless act == type

          number_first = first == id.number && years.include?(second)
          year_first = years.include?(first) && second == id.number
          return number_first if number_first != year_first
        end
        nil
      end

      def docidentifier
        [
          Bib::Docidentifier.new(type: "EU", content: pubid.to_s, primary: true),
          Bib::Docidentifier.new(type: "CELEX", content: "CELEX #{@row['celex']}"),
          Bib::Docidentifier.new(type: "ELI", content: @row["eli"]),
        ]
      end

      def title
        text = @row["title"]&.sub(EEA_NOTE, "")
        return [] if text.nil? || text.empty?

        [Bib::Title.new(type: "main", content: text, language: "en", script: "Latn")]
      end

      #
      # `issued`: the date of the document (adoption or signature).
      # `implemented`: the first entry into force; an act can enter into
      # force in stages (`2016/679`: 2016-05-24, then 2018-05-25).
      #
      def date
        dates = []
        dates << Bib::Date.new(type: "issued", at: @row["date"]) if @row["date"]
        force = @row["force"].to_s.split.grep_v(PLACEHOLDER_DATE).min
        dates << Bib::Date.new(type: "implemented", at: force) if force
        dates
      end

      #
      # Authors from the corporate-body authority (`…/corporate-body/EP`,
      # with its English label), ordered by code; the Publications Office
      # publishes every act.
      #
      def contributor
        authors = @row["authors"].to_s.split("\n").filter_map do |line|
          uri, label = line.split("|", 2)
          code = uri.to_s.split("/").last
          next if code.to_s.empty?

          [code, label.to_s.empty? ? code : label]
        end
        authors.uniq.sort.map { |code, name| contrib("author", code, name) } <<
          contrib("publisher", *PUBLISHER)
      end

      def contrib(role, code, name)
        org = Bib::Organization.new(
          name: [Bib::TypedLocalizedString.new(content: name)],
          abbreviation: Bib::LocalizedString.new(content: code),
        )
        Bib::Contributor.new(role: [Bib::Contributor::Role.new(type: role)],
                             organization: org)
      end

      def status
        stage = { "1" => "in-force", "0" => "not-in-force" }[@row["inforce"]]
        Bib::Status.new(stage: Bib::Status::Stage.new(content: stage)) if stage
      end

      #
      # The acts this act repeals and amends, by CELEX: the target's act
      # identifier is not in the row, and a CELEX number cannot give it.
      #
      def relation
        { "repeals" => "obsoletes", "amends" => "updates" }.flat_map do |key, type|
          @row[key].to_s.split.map do |celex|
            docid = Bib::Docidentifier.new(type: "CELEX", content: "CELEX #{celex}")
            Bib::Relation.new(type: type, bibitem: Bib::ItemData.new(docidentifier: [docid]))
          end
        end
      end

      def source
        [Bib::Uri.new(type: "src", content: "#{EURLEX}#{@row['celex']}")]
      end

      def ext
        doctype = pubid.class.name.split("::").last.downcase
        Bib::Ext.new(doctype: Bib::Doctype.new(content: doctype), flavor: "eu")
      end
    end
  end
end
