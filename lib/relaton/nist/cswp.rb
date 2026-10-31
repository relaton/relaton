require "yaml"

module Relaton
  module Nist
    #
    # CSWP ids the CSRC pubs-export feed does not list (relaton#406): the
    # legacy dated ids from before the series was numbered, and the
    # translations. The table (`cswp.yaml`) is built from the NIST Library RIS
    # files; see the header of that file.
    #
    # This file loads no flavor model at require time, so the processor can
    # ask #lookup on the cold path. #translation_item needs the models.
    #
    module Cswp
      # ISO 639-2 code of a translation => [ISO 639-1 code, ISO 15924 script]
      LANGUAGES = {
        "ara" => %w[ar Arab], "bul" => %w[bg Cyrl], "fre" => %w[fr Latn],
        "gre" => %w[el Grek], "ind" => %w[id Latn], "jpn" => %w[ja Jpan],
        "kor" => %w[ko Kore], "may" => %w[ms Latn], "nor" => %w[no Latn],
        "pol" => %w[pl Latn], "por" => %w[pt Latn], "spa" => %w[es Latn],
        "ukr" => %w[uk Cyrl]
      }.freeze

      class << self
        # @return [Hash] the table as written in cswp.yaml
        def table
          @table ||= YAML.load_file File.expand_path("cswp.yaml", __dir__)
        end

        #
        # The comparable form of a CSWP reference: no publisher, the
        # separators (".", "(...)") read as spaces, upper case.
        # "NIST CSWP 6(spa)", "NIST.CSWP.6.spa" and "NIST CSWP 6 spa" all
        # give "CSWP 6 SPA".
        #
        # @param ref [String]
        # @return [String]
        def normalize(ref)
          ref.to_s.sub(/\ANIST[.\s]+/i, "").gsub(/[().]/, " ").squeeze(" ").strip.upcase
        end

        #
        # Find a reference in the table.
        #
        # @param ref [String]
        # @return [Array, nil] `[:legacy, numbered id, dated id]` for a
        #   legacy id of an English CSWP, `[:translation, entry]` for a
        #   translation (dated or numbered), nil otherwise
        def lookup(ref)
          key = normalize ref
          return unless key.start_with? "CSWP "

          key = key.delete_prefix "CSWP "
          dated, target = legacy[key]
          entry = translations[(target || key).upcase]
          return [:translation, entry] if entry

          [:legacy, "NIST CSWP #{target}", "NIST CSWP #{dated}"] if target
        end

        #
        # Build the record of a translation from its RIS fields.
        #
        # @param entry [Hash] a translation entry from #lookup
        # @return [Relaton::Nist::ItemData]
        def translation_item(entry) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
          number, lang_code = entry[:id].split
          language, script = LANGUAGES.fetch lang_code
          id = "NIST CSWP #{number}(#{lang_code})"
          ItemData.new(
            type: "standard",
            docidentifier: [
              Docidentifier.new(content: id, type: "NIST", primary: true),
              Docidentifier.new(content: entry[:doi].split("/").last, type: "DOI"),
            ],
            title: [Bib::Title.new(content: entry[:title], language: "en", script: "Latn")],
            source: [Bib::Uri.new(type: "doi", content: "https://doi.org/#{entry[:doi]}")],
            date: [Date.new(type: "published", at: entry[:year])],
            contributor: entry[:authors].map { |name| author name } << publisher,
            language: [language],
            script: [script],
            relation: [original_relation("NIST CSWP #{number}")],
            place: [Bib::Place.new(city: "Gaithersburg", region: [Bib::Place::RegionType.new(iso: "MD")])],
            ext: Ext.new(doctype: Doctype.new(content: "standard"), flavor: "nist"),
          )
        end

        private

        # dated id (upper case) => [dated id, numbered id]
        def legacy
          @legacy ||= table["legacy"].to_h { |dated, numbered| [dated.upcase, [dated, numbered]] }
        end

        # translation id (upper case) => entry
        def translations
          @translations ||= table["translations"].to_h do |id, fields|
            [id.upcase, fields.transform_keys(&:to_sym).merge(id: id, authors: fields["authors"] || [])]
          end
        end

        # @param name [String] RIS author, "Surname, Forename"
        # @return [Bib::Contributor]
        def author(name)
          surname, forename = name.split(/,\s*/, 2)
          fullname = Bib::FullName.new(
            surname: Bib::LocalizedString.new(content: surname, language: "en", script: "Latn"),
            forename: [Bib::FullNameType::Forename.new(content: forename, language: "en", script: "Latn")],
          )
          Bib::Contributor.new(
            person: Bib::Person.new(name: fullname),
            role: [Bib::Contributor::Role.new(type: "author")],
          )
        end

        # @return [Bib::Contributor]
        def publisher
          org = Bib::Organization.new(
            name: [Bib::TypedLocalizedString.new(content: "National Institute of Standards and Technology")],
            abbreviation: Bib::LocalizedString.new(content: "NIST"),
          )
          Bib::Contributor.new(organization: org, role: [Bib::Contributor::Role.new(type: "publisher")])
        end

        # @param id [String] the original's id
        # @return [Relaton::Nist::Relation]
        def original_relation(id)
          bib = ItemData.new(
            formattedref: Bib::Formattedref.new(content: id),
            docidentifier: [Docidentifier.new(content: id, type: "NIST", primary: true)],
          )
          Relation.new(type: "translatedFrom", bibitem: bib)
        end
      end
    end
  end
end
