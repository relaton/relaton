# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Rules
        # The JIS rule set, moved verbatim from the metanorma-jis
        # flavor's JisElements: the host-title-first component part
        # (with the 1.x orphaned close paren), the host-series
        # fallback, and the book-family extent. Select from pack data:
        #   rules: { component_part: jis_component_part, ... }
        module Jis
          # The host of a part citation, 1.x parity: the host title,
          # then the host's principal creator, closed by a paren the
          # 1.x cleanup had orphaned when the host role came out empty
          # ("Collected Essays UNICEF)")
          class JisComponentPart < Elements::ComponentPart
            def render
              return "" if host_title_text.empty?

              "#{host_title_text} #{host_creators}#{close_paren}".strip
            end

            private

            def host_creators
              author = Array(host&.contributor)
                .find { |c| has_role?(c, "author") } or return ""

              person = author.person
              if person.nil?
                Array(author.organization&.name).map { |n| localized(n) }
                  .reject(&:empty?).join(", ")
              else
                host_person_name(author, first: true)
              end
            end

            def close_paren
              @i18n.punct_fetch("close-paren", ")")
            end
          end

          # A part cites its host's series when it carries none of its
          # own (the 1.x series fallback to the host document)
          class JisSeries < Elements::Series
            private

            def series
              super || Array(host_relation&.bibitem&.series).first
            end

            def host_relation
              Array(@model.relation).find do |r|
                Elements::ComponentPart::HOST_RELATION_TYPES.include?(r.type)
              end
            end
          end

          # The book-family extent carries the volume and the page
          # only, and repeated localities of one type collapse to the
          # last declared (the 1.x per-type merge)
          class JisExtent < Elements::Extent
            def render
              return super unless book_family?

              [volume_part, page_part].reject(&:empty?).join(" ")
            end

            private

            def book_family?
              %w[book inbook incollection inproceedings proceedings]
                .include?(@model.type.to_s)
            end

            def volume_part
              loc = pick("volume") or return ""
              loc.reference_from.to_s.empty? ? "" :
                unit("volume", loc.reference_from)
            end

            def page_part
              loc = pick("page") or return ""
              from = loc.reference_from.to_s
              to = loc.reference_to.to_s
              if to.empty? || to == from
                unit("page", from)
              else
                unit("pages", "#{from}#{@i18n.label('date_range')}#{to}")
              end
            end

            # The last locality of a type wins (the 1.x merge)
            def pick(type)
              localities.reverse.find { |l| l.type == type }
            end
          end
        end
      end
    end
  end
end
