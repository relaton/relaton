# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      module Rules
        # The NIST rule set, moved verbatim from the metanorma-nist
        # flavor's NistElements: the corporate creator forms, the
        # series derivation from nist-long identifiers, the draft
        # stage forms, the identifier order, and the component-part
        # host citation. Select from pack data:
        #   rules: { creator: nist_series_publisher, ... }
        module Nist
          NIST_AND_ABBREV =
            ["NIST", "National Institute of Standards and Technology"].freeze

          STAGE_PRINT = {
            "draft-internal" => "Internal Draft",
            "draft-wip" => "Work-in-Progress Draft",
            "draft-prelim" => "Preliminary Draft",
            "draft-public" => "Public Draft",
            "draft-approval" => "Approval Draft",
            "final" => "Final",
            "final-review" => "Under Review",
          }.freeze

          FIPS_PUBLISHER = "U.S. Department of Commerce, Washington, D.C."
          NIST_PUBLISHER = "National Institute of Standards and Technology, " \
                           "Gaithersburg, MD"

          HOST_RELATION_TYPES = %w[partOf includedIn].freeze

          # The partOf/includedIn host and its publication year: shared
          # by the component part and the host-date fallback of the
          # date element
          module HostDate
            def relation_host
              Array(@model.relation).find do |r|
                HOST_RELATION_TYPES.include?(r.type)
              end&.bibitem
            end

            def host_date_year
              h = relation_host or return ""
              d = Array(h.date).find(&:published) ||
                  Array(h.date).find { |x| x.type.nil? } ||
                  Array(h.date).find { |x| x.type == "issued" } ||
                  Array(h.date).first or return ""
              v = d.at || d.from || d.to or return ""
              begin
                v.to_date.year.to_s
              rescue ArgumentError, TypeError
                v.to_s[/\d{4}/].to_s
              end
            end
          end

          # NIST-aware element base: NIST Standard Reference documents
          # are detected by identifier type or publisher
          class Base < Element
            def present?
              !render.to_s.empty?
            end

            private

            def nist?
              return true if Array(@model.docidentifier).any? do |d|
                d.type.to_s.start_with?("NIST")
              end

              Array(@model.contributor).select { |c| has_role?(c, "publisher") }
                .any? do |c|
                org = c.organization or next false

                Array(org.name).any? { |n| NIST_AND_ABBREV.include?(n.content) } ||
                  org.abbreviation&.content == "NIST"
              end
            end

            def series_title
              Array(@model.series).first&.title&.first&.content.to_s
            end
          end

          # The series publisher block, parenthesized, after the title
          class NistPublisher < Base
            def render
              if series_title == "NIST Federal Information Processing Standards"
                return " (#{FIPS_PUBLISHER})"
              end

              nist? ? " (#{NIST_PUBLISHER})" : ""
            end
          end

          # The NIST draft form ("Draft (Third Public Draft)")
          class NistDraft < Base
            def render
              stage = @model.status&.stage&.content.to_s
              return "" unless stage.start_with?("draft") && nist?

              "Draft (#{iteration(stage)} #{STAGE_PRINT.fetch(stage, stage)})"
            end

            private

            def iteration(stage)
              iter = @model.status&.iteration.to_s
              return "Initial" if iter.empty? || iter == "1"
              return "Final" if iter.casecmp("final").zero?

              spellout_ordinal(iter.to_i)
            end

            # The language packs carry ordinal word labels; beyond
            # their reach the numeric suffix form carries the value
            def spellout_ordinal(num)
              word = @i18n.label("ordinal_word_#{num}")
              return word.capitalize unless word == "ordinal_word_#{num}"

              "#{num}#{ordinal_suffix(num)}"
            end

            def ordinal_suffix(num)
              case num % 100
              when 11, 12, 13 then "th"
              else
                case num % 10
                when 1 then "st"
                when 2 then "nd"
                when 3 then "rd"
                else "th"
                end
              end
            end
          end

          # The NIST series form ("NIST Special Publication (SP)
          # 800-116 Rev. 1"). A series carrying a formattedref renders
          # it verbatim; the number joins the partnumber ("800-116.1"),
          # and the edition carries the revision. NIST documents
          # without a series element derive it from the nist-long
          # identifier
          class NistSeries < Base
            def render
              s = Array(@model.series).first
              return derived_series unless s

              formatted = localized(s.formattedref)
              return formatted unless formatted.empty?

              title = localized(Array(s.title).first)
              return "" if title.empty?

              [title, parens(s), number(s)].reject(&:empty?).join(" ")
            end

            private

            def derived_series
              long = Array(@model.docidentifier).find do |d|
                d.type == "nist-long"
              end&.content.to_s
              return "" if long.empty?

              title = long[/\A(NIST [A-Za-z ]+?) \d/, 1] || ""
              return "" if title.empty?

              [title, parens_derived(long), number_derived(long)]
                .reject(&:empty?).join(" ")
            end

            def parens_derived(long)
              # strip the NIST sigla before the whitespace strip: the
              # 1.x order left a bare "NIST" parenthesized
              abbr = long[/\A[A-Z.]+ /, 0].to_s.sub(/\ANIST /, "").strip
              abbr.empty? ? "" : "(#{abbr})"
            end

            def number_derived(long)
              num = long[/\A[NISTa-z. ]*([0-9][0-9A-Za-z.-]*)/, 1].to_s
              num.empty? ? num : with_revision(num)
            end

            def parens(s)
              abbr = localized(s.abbreviation).sub(/\ANIST /, "")
              abbr.empty? ? "" : "(#{abbr})"
            end

            def number(s)
              num = s.number.to_s
              unless s.partnumber.to_s.empty?
                num = num.empty? ? s.partnumber.to_s : "#{num}.#{s.partnumber}"
              end
              num = @model.docnumber.to_s if num.empty? && nist?
              num.empty? ? num : with_revision(num)
            end

            def with_revision(num)
              rev = @model.edition&.content.to_s.sub(/\ARevision /, "")
              rev.empty? ? num : "#{num} Rev. #{rev}"
            end
          end
        end
      end
    end
  end
end

module Relaton
  module Render
    module Iso690
      module Rules
        module Nist
          # The NIST identifier order: the authoritative identifiers
          # (ISO, IEC, ...) before the kind-rendered ISBN/DOI/ISSN
          # group; NIST documents cite the NIST identifier alone (the
          # biblio tag)
          class NistIdentifier < Elements::Identifier
            OTHER_TYPES = %w[ISBN ISSN DOI].freeze

            def render
              return "" if nist?

              auth, other = unscoped_ids.partition do |d|
                !OTHER_TYPES.include?(d.type)
              end
              (auth + other).map { |d| render_id(d) }.reject(&:empty?)
                .join(". ")
            end

            private

            def nist?
              Array(@model.docidentifier).any? do |d|
                d.type.to_s.start_with?("NIST")
              end || Array(@model.contributor).any? do |c|
                next false unless has_role?(c, "publisher")

                org = c.organization or next false

                Array(org.name).any? { |n| NIST_AND_ABBREV.include?(n.content) } ||
                  org.abbreviation&.content == "NIST"
              end
            end

            def unscoped_ids
              Array(@model.docidentifier).reject do |d|
                Elements::Identifier::INTERNAL_TYPES.include?(d.type) ||
                  !d.scope.to_s.empty? || d.content.to_s.strip.empty?
              end
            end

            # The NIST ISBN and ISSN kinds cite the kind label with a
            # colon
            def render_id(docidentifier)
              return "#{docidentifier.type}: #{docidentifier.content}" if
                %w[ISBN ISSN].include?(docidentifier.type)

              super
            end
          end

          # The NIST component-part order: the host editors before the
          # host title, the host date after the production
          # ("In: Pellegrini AD, Smith PK (Eds.) <em>The nature of
          # play</em> (New York, NY: Guilford Press), 2005")
          class NistComponentPart < Elements::ComponentPart
            include HostDate

            def render
              h = relation_host or return ""
              out = +"#{lead}#{host_names(h)}"
              eds = host_editors(h)
              out += " (#{@i18n.label(eds.one? ? "ed" : "eds")})" unless
                eds.empty?
              out += " #{host_title}" unless host_title_text.empty?
              production = host_production_text(h)
              out += " (#{production})" unless production.empty?
              date = host_date_year
              out += ", #{date}" unless date.empty?
              out
            end

            private

            def host_editors(h)
              Array(h.contributor).select { |c| has_role?(c, "editor") }
            end

            def host_names(h)
              names = host_editors(h).map { |c|
                person = c.person or next ""

                [person_surname(person), person_given(person)].reject(&:empty?)
                  .join(" ")
              }.reject(&:empty?)
              join_names(names)
            end

            def host_production_text(h)
              Elements::Production.new(h, style: @style, i18n: @i18n)
                .render.to_s
            end
          end

          # A component part with no date of its own cites the host's
          class NistDate < Elements::PubDate
            include HostDate

            def render
              text = super.to_s
              text.empty? ? host_date_year : text
            end
          end

          # The series-position date segment of the 1.x templates: the
          # date carries its own leading comma ("<series>, 2018
          # (updated November 2018)"), so an absent date removes the
          # comma with it
          class NistSerialDate < Base
            def render
              text = pub_date or return ""

              ", #{text}#{updated_date}"
            end

            private

            def pub_date
              t = Elements::PubDate.new(@model, style: @style, i18n: @i18n)
                .render.to_s
              t.empty? ? nil : t
            end

            def updated_date
              Elements::Updated.new(@model, style: @style, i18n: @i18n).render
            end
          end

          # The FIPS creator form: the series names the corporate
          # creator; standards without personal creators cite their
          # publisher's name, monographs cite nothing (their "(n.d.)"
          # comes from the perType fallback)
          class NistCreator < Elements::Creator
            def render
              return fips_creator if fips_series?

              super
            end

            def plain_render
              return fips_creator if fips_series?

              super
            end

            private

            def fallback_name
              return "" if %w[monograph continuing component_part]
                .include?(Kinds.kind_for(@model.type))

              publishers = contributors("publisher").filter_map do |c|
                localized(Array(c.organization&.name).first)
              end
              publishers.reject(&:empty?).first.to_s
            end

            def fips_series?
              Array(@model.series).first&.title&.first&.content ==
                "NIST Federal Information Processing Standards"
            end

            def fips_creator
              "National Institute of Standards and Technology"
            end
          end
        end
      end
    end
  end
end
