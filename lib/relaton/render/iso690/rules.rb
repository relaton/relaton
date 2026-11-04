# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      # The named-rule registry: presentation-of-models implementations
      # the engine ships once, addressable from pack data as
      # rules: { slot: rule_name }. Flavors migrate their ELEMENTS maps
      # onto registered rules; nothing references a flavor class.
      module Rules
        # The bare status: unparenthesized, no label ("Recommendation")
        class BareStatus < Elements::Status
          def render
            stage.to_s
          end
        end

        # The IEEE-SA identifiers: DOI and ISBN carry their kind label
        # with a colon ("DOI: https://doi.org/…")
        class IeeeIdentifier < Elements::Identifier
          private

          def render_id(docidentifier)
            return "#{docidentifier.type}: #{docidentifier.content}" if
              %w[DOI ISBN].include?(docidentifier.type)

            super
          end
        end

        # The IEEE component part: "in Pellegrini, A. D., and P. K.
        # Smith (eds.): <em>host</em>, production" — the names first,
        # the eds marker in the close paren, the host title after the
        # colon, the production after a comma
        class IeeeComponentPart < Elements::ComponentPart
          def render
            h = host or return ""
            out = +"in #{host_person_names(h)} (#{eds_label(h)}): "
            out += host_title.to_s
            production = Elements::Production
              .new(h, style: @style, i18n: @i18n).render.to_s
            out += ", #{production}" unless production.empty?
            out
          end

          private

          def host_editors(h)
            Array(h.contributor).select { |c| has_role?(c, "editor") }
          end

          def eds_label(h)
            @i18n.label(host_editors(h).one? ? "ed" : "eds")
          end

          # The IEEE host form: the first editor inverted, subsequent
          # editors direct
          def host_person_names(h)
            host_editors(h).each_with_index.map { |c, i|
              person = c.person or next ""

              if i.zero?
                [person_surname(person), person_given(person)]
                  .reject(&:empty?).join(", ")
              else
                [person_given(person), person_surname(person)]
                  .reject(&:empty?).join(" ")
              end
            }.reject(&:empty?).then { |names| join_names(names) }
          end
        end

        # The IEEE access date, bare and unbracketed
        # ("accessed September 3, 2019")
        class IeeeAccess < Elements::Access
          def render
            "#{@i18n.label('viewed')} #{date_text}"
          end
        end

        # The IEEE medium, capitalized and carrying its own trailing
        # comma ("Dataset,", "Preprint,")
        class IeeeMedium < Elements::Medium
          private

          def medium
            m = @model.medium or return ""
            text = m.carrier.to_s
            text = m.genre.to_s if text.empty?
            text = [m.form.to_s, m.size.to_s].reject(&:empty?)
              .join(", ") if text.empty?
            text.empty? ? "" : "#{text.sub(/^\w/) { |c| c.upcase }},"
          end
        end

        # The ITU identifiers: ISBN and ISSN carry their kind label
        # with a colon ("ISBN 92-61-12521-9")
        class ItuIdentifier < Elements::Identifier
          private

          def render_id(docidentifier)
            return "#{docidentifier.type}: #{docidentifier.content}" if
              %w[ISBN ISSN].include?(docidentifier.type)

            super
          end
        end

        # The IHO creator cites the affiliation's organization name
        # after the creator list ("D. Balenson, Internet Engineering
        # Task Force")
        class IhoCreator < Elements::Creator
          def render
            out = super.to_s
            aff = affiliation_names
            out.empty? || aff.empty? ? out : "#{out}, #{aff}"
          end

          private

          def affiliation_names
            creators.filter_map do |c|
              person = c.person or next ""

              Array(person.affiliation).filter_map do |a|
                Array(a.organization&.name).map(&:content).first.to_s
              end.reject(&:empty?).first.to_s
            end.reject(&:empty?).uniq.join(", ")
          end
        end

        # The IHO edition cites only for IHO-published documents, as
        # the raw numeric edition carrying its own label ("edition
        # 3.1.0"); worded editions ("Revision 1") cite as nothing
        class IhoEdition < Elements::Edition
          def render
            return "" unless iho_publisher?

            text = edition_text
            text.match?(/\A\d/) ? " edition #{text}" : ""
          end

          private

          def edition_text
            raw = @model.edition
            raw.respond_to?(:content) ? raw.content.to_s : raw.to_s
          end

          def iho_publisher?
            Array(@model.contributor).any? do |c|
              next false unless Array(c.role).any? do |r|
                r.is_a?(String) ? r == "publisher" : r.type == "publisher"
              end

              org = c.organization or next false
              names = Array(org.name).map(&:content) +
                      [org.abbreviation&.content.to_s]
              # a string array: %w[] would split the organization's
              # full name into words and never match it
              names.any? do |n|
                ["IHO", "International Hydrographic Organization"]
                  .include?(n)
              end
            end
          end
        end

        # The NIST, BIPM and JIS rule sets live in their own
        # autoloaded sections
        autoload :Nist, "relaton/render/iso690/rules/nist"
        autoload :Bipm, "relaton/render/iso690/rules/bipm"
        autoload :Jis, "relaton/render/iso690/rules/jis"

        REGISTRY = {
          "status_bare" => BareStatus,
          "itu_identifier" => ItuIdentifier,
          "ieee_identifier" => IeeeIdentifier,
          "ieee_component_part" => IeeeComponentPart,
          "ieee_access" => IeeeAccess,
          "ieee_medium" => IeeeMedium,
          "nist_creator" => Nist::NistCreator,
          "nist_date" => Nist::NistDate,
          "nist_serial_date" => Nist::NistSerialDate,
          "nist_series" => Nist::NistSeries,
          "nist_component_part" => Nist::NistComponentPart,
          "nist_identifier" => Nist::NistIdentifier,
          "nist_publisher" => Nist::NistPublisher,
          "nist_draft" => Nist::NistDraft,
          "iho_creator" => IhoCreator,
          "iho_edition" => IhoEdition,
          "bipm_creator" => Bipm::BipmCreator,
          "bipm_component_part" => Bipm::BipmComponentPart,
          "bipm_production" => Bipm::BipmProduction,
          "bipm_extent" => Bipm::BipmExtent,
          "bipm_medium" => Bipm::BipmMedium,
          "bipm_edition" => Bipm::BipmEdition,
          "bipm_volume" => Bipm::BipmVolume,
          "jis_component_part" => Jis::JisComponentPart,
          "jis_series" => Jis::JisSeries,
          "jis_extent" => Jis::JisExtent,
        }.freeze

        class << self
          def register(name, klass)
            REGISTRY[name.to_s] = klass
          end

          # A pack's rule selections become the renderer's element map;
          # caller-supplied elements win over the pack's selections
          def resolve(rules, elements = {})
            Array(rules).to_h { |slot, name| [slot.to_sym, fetch(name)] }
              .merge(elements || {})
          end

          private

          def fetch(name)
            REGISTRY.fetch(name.to_s) do
              raise ArgumentError, "unknown citation style rule #{name}"
            end
          end
        end
      end
    end
  end
end
