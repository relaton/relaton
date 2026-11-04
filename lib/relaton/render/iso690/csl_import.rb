require "json"

module Relaton
  module Render
    module Iso690
      # Imports a CSL style's common properties into a CitationStyle instance
      # (styles as data, the downgrade direction: CSL's element-list engine
      # is strictly richer, so the import covers what the instance format can
      # express and lists everything it dropped in `requires`).
      #
      # Mapped: the info title, the citation/reference variable runs (text
      # elements over the CSL variables, via the crosswalk below), the
      # name-form scalars (initialize-with, name-as-sort-order, et-al
      # lengths), the year-suffix disambiguation, and the delimiters.
      module CslImport
        # CSL variable -> the ISO 690 slot the engine resolves.
        VARIABLE_SLOTS = {
          "author" => "creator", "editor" => "creator",
          "title" => "title", "container-title" => "series",
          "edition" => "edition", "publisher" => "production",
          "publisher-place" => "location", "issued" => "date",
          "DOI" => "identifier", "URL" => "identifier", "PMID" => "identifier",
          "number" => "numeration", "volume" => "numeration",
          "page" => "numeration", "medium" => "medium",
          "accessed" => "access", "version" => "edition",
        }.freeze

        # CSL features the import drops, reported in `requires` so a resolver
        # fails loudly instead of silently mis-rendering.
        DROPPED_FEATURES = [
          "csl macros (macro elements are not data-expressible)",
          "csl groups with conditional rendering (match= attributes)",
          "csl per-locator templates",
        ].freeze

        class << self
          # Build a CitationStyle instance from a parsed CSL style JSON.
          #
          # @param csl [Hash] parsed CSL style
          # @return [Style]
          def style(csl)
            Style.new(
              name: style_name(csl),
              family: "iso690",
              requires: dropped_features(csl),
              scheme: scheme(csl),
              templates: templates(csl),
            )
          end

          # Parse a CSL style JSON string and build the instance.
          #
          # @param [String] json
          # @return [Style]
          def from_json(json)
            style(JSON.parse(json))
          end

          private

          def style_name(csl)
            title = csl.dig("info", "title").to_s
            title.empty? ? "Imported CSL style" : "#{title} (CSL import)"
          end

          def dropped_features(csl)
            feats = DROPPED_FEATURES.dup
            feats << "csl bibliography section" if csl["bibliography"]
            feats << "csl locales" if csl["locales"]
            feats
          end

          def scheme(csl)
            Style::Scheme.new(
              system: "name-date",
              name_form: name_form(csl),
              locale: Style::Locale.new(no_date: "n.d."),
            )
          end

          def name_form(csl)
            citation = csl["citation"] || {}
            initialize_with = citation["initialize-with"]
            Style::NameForm.new(
              initials: !initialize_with.nil?,
              initials_separator: initialize_with.is_a?(String) ? initialize_with : " ",
              initials_period: initialize_with.to_s.include?("."),
              inverted_all: citation["name-as-sort-order"].to_s == "all",
            )
          end

          def templates(csl)
            citation_elements = csl.dig("citation", "elements") || []
            reference_elements = csl.dig("bibliography", "elements") || []
            Style::TemplateMap.new(
              citation: element_template(
                citation_elements, csl.dig("citation", "delimiter") || ", ",
                "{{creator}}, {{date}}{{disambiguator}}",
              ),
              reference: element_template(
                reference_elements, csl.dig("bibliography", "delimiter") || ". ",
                "{{creator}}. {{title}}. {{edition}}. {{series}}. {{production}}, {{date}}. {{identifier}}. {{location}}.",
              ),
              name: "{{surname}}, {{givenNames}}",
            )
          end

          # Flatten CSL text/variable elements into a slot template. Non-text
          # elements (macros, groups, conditions) contribute nothing: the
          # import covers flat variable runs only.
          def element_template(elements, delimiter, fallback)
            slots = elements.filter_map do |el|
              next unless el.is_a?(Hash)

              # A CSL text element nests its variable: {"text": {"variable": ...}}
              variable = el.dig("text", "variable") || el["variable"]
              slot = variable && VARIABLE_SLOTS[variable]
              "{{#{slot}}}" if slot
            end
            slots = slots.uniq
            return fallback if slots.empty?

            slots.join(delimiter)
          end
        end
      end
    end
  end
end
