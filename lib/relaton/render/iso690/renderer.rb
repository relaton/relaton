# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      # Public API: relaton model in, citation string out. The style
      # instance supplies every rendering decision; this class only wires
      # the template evaluator to the field resolver. No XML, no
      # intermediate hashes.
      class Renderer
        DEFAULT_STYLE = "author-date"

        class << self
          def render(model, style: DEFAULT_STYLE, lang: "en", script: "Latn",
                     elements: {})
            new(style: style, lang: lang, script: script,
                elements: elements).render(model)
          end

          def citation(model, disambiguator: nil, style: DEFAULT_STYLE,
                       lang: "en", script: "Latn")
            new(style: style, lang: lang, script: script)
              .citation(model, disambiguator: disambiguator)
          end
        end

        def initialize(style: DEFAULT_STYLE, lang: "en", script: "Latn",
                       labels: {}, elements: {})
          @style = Style.load(style)
          @elements = Rules.resolve(@style.rules, elements)
          @i18n = I18n.load(lang)
          @i18n.overlay_hash!(labels) unless labels.empty?
          # The style instance is the citation-style authority: its
          # declared strings win over the caller's generic i18n hash
          @i18n.overlay!(@style.scheme.locale)
          @script = script
        end

        def render(model, disambiguator: nil)
          kind = @style.kind_for(model.type)
          template = @style.template_for(kind, home: home_docid?(model))
          out = Template.new(template).evaluate(
            Fields.new(model, style: @style, i18n: @i18n,
                       disambiguator: disambiguator,
                       elements: @elements).to_h,
          )
          raise ::Relaton::Render::Unrenderable,
                "no renderable elements" if out.strip.empty?

          out
        end

        def home_docid?(model)
          types = Array(@style.scheme.home_docid_type)
          return false if types.empty?

          Array(model.docidentifier).any? { |d| types.include?(d.type) }
        end

        # A creator list alone (flavors' document-history name forms)
        def render_creators(model)
          Elements.build(:creator, model, style: @style, i18n: @i18n,
                         short: true, elements: @elements).render
        end

        # The short cite: the reference with the first-biblio marker
        def render_short(model, delim)
          kind = @style.kind_for(model.type)
          template = @style.short_template_for(kind,
                                               home: home_docid?(model)) ||
            @style.template_for(kind, home: home_docid?(model))
          Template.new(template).evaluate_short(
            Fields.new(model, style: @style, i18n: @i18n, short: true,
                       elements: @elements).to_h,
            delim,
          )
        rescue ::Relaton::Render::Unrenderable
          ""
        end

        # The in-text creator with its et-al truncation: the
        # author-date tag's author part
        def in_text_author(model)
          Elements.build(:creator, model, style: @style, i18n: @i18n,
                         elements: @elements).in_text
        end

        # The author-date in-text capsule ("Aluffi <em>et al.</em>
        # 2022a"): the in-text creator and the disambiguated date
        def author_date_citation(model, disambiguator: nil)
          f = Fields.new(model, style: @style, i18n: @i18n,
                         disambiguator: disambiguator,
                         elements: @elements).to_h
          [in_text_author(model), f["disambiguateddate"].text]
            .reject(&:empty?).join(" ")
        end

        # The bracketed author-date in-text capsule ("Aluffi （2022）"):
        # the author and the PLAIN date (un-disambiguated, the 1.x
        # citetemplate's {{ date }}) in the locale's parentheses
        def bracketed_date_citation(model, **)
          f = Fields.new(model, style: @style, i18n: @i18n,
                         elements: @elements).to_h
          date = f["date"].text
          return "" if date.empty?

          open = @i18n.punct_fetch("open-paren", "(")
          close = @i18n.punct_fetch("close-paren", ")")
          [in_text_author(model), "#{open}#{date}#{close}"]
            .reject(&:empty?).join(" ")
        end

        # The disambiguated date alone (the citation renderings' date)
        def disambiguated_date(model, disambiguator: nil)
          Fields.new(model, style: @style, i18n: @i18n,
                     disambiguator: disambiguator,
                     elements: @elements).to_h["disambiguateddate"].text
        end

        def short_from_reference?
          @style.scheme.short_from_reference
        end

        # The title citation ("{{ title }}" in the 1.x citetemplate):
        # the title element's plain form, no style markers
        def title_citation(model)
          Elements.build(:title, model, style: @style, i18n: @i18n,
                         elements: @elements).plain
        end

        # The in-text author key (the principal creator's surname, as
        # the citation renders it): the batch disambiguation groups by
        # it
        def author_key(model)
          Fields.new(model, style: @style, i18n: @i18n,
                     elements: @elements).to_h["surname"].text
        end

        # In-text form: SURNAME, year + disambiguator (name-and-date)
        def citation(model, disambiguator: nil)
          Template.new(@style.templates.citation).evaluate(
            Fields.new(model, style: @style, i18n: @i18n,
                       disambiguator: disambiguator,
                       elements: @elements).to_h,
          )
        end
      end
    end
  end
end
