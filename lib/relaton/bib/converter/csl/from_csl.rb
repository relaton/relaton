# frozen_string_literal: true

module Relaton
  module Bib
    module Converter
      module Csl
        # CSL-JSON entry -> ItemData. The downgrade direction: a CSL record
        # is a flat citation, so fields it does not express are left out
        # rather than invented. The mirror of Converter::Bibtex::FromBibtex.
        class FromCsl
          # The reverse of ENTRY_TYPES for the types the export emits; any
          # other CSL type is kept as written.
          TYPES = {
            "article-journal" => "article", "chapter" => "inbook",
            "paper-conference" => "inproceedings", "webpage" => "webresource",
          }.freeze

          # @param entry [Hash] one CSL-JSON entry
          def initialize(entry)
            @entry = entry
          end

          # @return [Relaton::Bib::ItemData]
          def transform # rubocop:disable Metrics/MethodLength
            ItemData.new(
              id: @entry["id"],
              docidentifier: fetch_docid,
              type: fetch_type,
              title: fetch_title,
              contributor: fetch_contributor,
              date: fetch_date,
              abstract: fetch_abstract,
              extent: fetch_extent,
              edition: fetch_edition,
              series: fetch_series,
              source: fetch_source,
              language: fetch_language,
              keyword: fetch_keyword,
              relation: fetch_relation,
            )
          end

          private

          # @return [Array<Relaton::Bib::Docidentifier>]
          def fetch_docid
            docid = [Docidentifier.new(content: @entry["id"].to_s, primary: true)]
            docid << Docidentifier.new(content: @entry["ISBN"].to_s, type: "isbn") if @entry["ISBN"]
            docid << Docidentifier.new(content: @entry["ISSN"].to_s, type: "issn") if @entry["ISSN"]
            docid
          end

          # @return [String, nil]
          def fetch_type
            TYPES[@entry["type"]] || @entry["type"]
          end

          # @return [Array<Relaton::Bib::Title>]
          def fetch_title
            return [] unless @entry["title"]

            [Title.new(type: "main", content: @entry["title"])]
          end

          # @return [Array<Relaton::Bib::Contributor>]
          def fetch_contributor
            contribs = []
            fetch_person("author") { |c| contribs << c }
            fetch_person("editor") { |c| contribs << c }

            return contribs unless @entry["publisher"]

            contribs << Contributor.new(
              organization: Organization.new(name: [TypedLocalizedString.new(content: @entry["publisher"])]),
              role: [Contributor::Role.new(type: "publisher")],
            )
            contribs
          end

          # CSL names are {family:, given:} or a bare {literal:}.
          #
          # @param role [String] contributor role
          def fetch_person(role, &_)
            Array(@entry[role]).each do |name|
              yield Contributor.new(person: Person.new(name: build_name(name)), role: [Contributor::Role.new(type: role)])
            end
          end

          # @param name [Hash] CSL name variable
          # @return [Relaton::Bib::FullName]
          def build_name(name)
            return FullName.new(completename: LocalizedString.new(content: name["literal"])) if name["literal"]

            fore = name["given"].to_s.split
            FullName.new(
              surname: LocalizedString.new(content: name["family"].to_s),
              forename: fore.map { |fn| FullNameType::Forename.new(content: fn) },
            )
          end

          # @return [Array<Relaton::Bib::Date>]
          def fetch_date
            { "issued" => "published", "accessed" => "accessed" }.filter_map do |field, type|
              parts = @entry.dig(field, "date-parts")&.first
              next unless parts

              Bib::Date.new(type: type, at: iso_date(parts))
            end
          end

          # @param parts [Array<Integer>] [year], [year, month] or [year, month, day]
          # @return [String]
          def iso_date(parts)
            format("%04d", parts[0]).tap do |iso|
              iso << "-%02d" % parts[1] if parts[1]
              iso << "-%02d" % parts[2] if parts[2]
            end
          end

          # @return [Array<Relaton::Bib::Abstract>]
          def fetch_abstract
            return [] unless @entry["abstract"]

            [Abstract.new(content: @entry["abstract"])]
          end

          # @return [Array<Relaton::Bib::Extent>]
          def fetch_extent
            locs = []
            locs << Locality.new(type: "volume", reference_from: @entry["volume"].to_s) if @entry["volume"]
            if @entry["page"]
              from, to = @entry["page"].to_s.split("-", 2)
              locs << Locality.new(type: "page", reference_from: from, reference_to: to)
            end
            locs.any? ? [Extent.new(locality: locs)] : []
          end

          # @return [Relaton::Bib::Edition, nil]
          def fetch_edition
            Edition.new(content: @entry["edition"].to_s) if @entry["edition"]
          end

          # @return [Array<Relaton::Bib::Series>]
          # container-title is the journal for article types and the book for
          # chapters; the chapter shape maps to partOf, the journal shape to
          # a series — the same split FromBibtex makes for journal/booktitle.
          def fetch_series
            return [] unless container_title && fetch_type != "inbook"

            [Series.new(
              type: "journal",
              title: Title.new(content: container_title),
              number: @entry["number"]&.to_s,
            )]
          end

          # @return [Array<Relaton::Bib::Uri>]
          def fetch_source
            source = []
            source << Uri.new(type: "src", content: @entry["URL"]) if @entry["URL"]
            source << Uri.new(type: "doi", content: @entry["DOI"]) if @entry["DOI"]
            source
          end

          # @return [Array<String>]
          def fetch_language
            return [] unless @entry["language"]

            sub = @entry["language"].split("-").first
            [Iso639[sub]&.alpha2 || sub]
          end

          # @return [Array<Relaton::Bib::Keyword>]
          def fetch_keyword
            Array(@entry["keyword"]).map do |kw|
              Keyword.new(vocab: LocalizedString.new(content: kw))
            end
          end

          # @return [Array<Relaton::Bib::Relation>]
          def fetch_relation
            return [] unless container_title && fetch_type == "inbook"

            ttl = Title.new(type: "main", content: container_title)
            [Relation.new(type: "partOf", bibitem: ItemData.new(title: [ttl]))]
          end

          def container_title
            @entry["container-title"]
          end
        end
      end
    end
  end
end
