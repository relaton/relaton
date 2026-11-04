# frozen_string_literal: true

module Relaton
  module Render
    # Compatibility entry point (relaton-render#90).
    #
    # The v2 engine replaced the liquid/config/i18n machinery with the
    # template evaluator over CitationStyle instances
    # (Relaton::Render::Iso690). isodoc main's render-isodoc subclasses
    # this constant, so it must exist for all-git-main stacks to boot.
    # This facade delegates rendering to the v2 engine; the retired
    # options (config:, template overrides in liquid syntax) are ignored
    # with one warning — migrate to a CitationStyle instance, which
    # expresses everything the old config.yml did (see the citation
    # module in relaton-models).
    class General
      # The eref `style=` vocabulary metanorma-standoc validates against
      # (cleanup/xref.rb reads citetemplate.template_raw's keys) — the
      # 1.x default config's top-level citation styles.
      CITE_STYLES = %i[
        author_date author_date_br author date reference_tag title
        title_reference_tag short
      ].freeze

      CiteTemplate = Struct.new(:template_raw)

      def initialize(options = {})
        options = deep_symbolize(options)
        @lang = options[:language] || options[:lang] || "en"
        renderer_opts = { lang: @lang, script: options[:script] || "Latn",
                          labels: options[:i18nhash] || {} }
        # A flavor names its own CitationStyle instance (name or YAML path)
        options[:style] and renderer_opts[:style] = options[:style]
        @renderer = Iso690::Renderer.new(**renderer_opts)
        @renderer_opts = renderer_opts
        @renderers_by_lang = {}
        warn_general_config if options[:config]
      end

      # A collection's items may each declare their own language; the
      # renderer localizes by language, so a reference renders in its
      # own language within a document of another (the 1.x plateau
      # per-reference behaviour)
      def renderer_for(lang)
        return @renderer if lang.nil? || lang == @lang

        @renderers_by_lang[lang] ||= Iso690::Renderer.new(
          **@renderer_opts.merge(lang: lang,
                                 script: %w(ja ko zh).include?(lang) ? nil : "Latn")
        )
      end

      def render(model, embedded: false, **opts)
        model = to_model(model)
        text =
          if model.respond_to?(:formattedref) && model.formattedref
            model.formattedref.content
          else
            # a collection's items may each declare their own language;
            # the single-item render routes like render_all does
            renderer_for(Array(model.language).first).render(model, **opts)
          end
        embedded ? text : "<formattedref>#{text}</formattedref>"
      end

      def citation(model, **opts)
        @renderer.citation(to_model(model), **opts)
      end

      # isodoc's references rendering: renderings[id][:formattedref]
      # feeds the <formattedref> of every bibitem (isodoc
      # presentation_function/refs.rb).
      def render_all(bib, type: "author-date")
        items = facade_bibitems(bib) or return nil
        disambiguators = date_disambiguators(items)
        items.each_with_object({}).with_index do |(item, m), i|
          renderer = renderer_for(Array(item.language).first)
          ref = begin
            renderer.render(item, disambiguator: disambiguators[item.id])
          rescue ::Relaton::Render::Unrenderable
            next
          end
          m[item.id] = {
            author: renderer.in_text_author(item),
            date: renderer.disambiguated_date(item,
                                              disambiguator:
                                                disambiguators[item.id]),
            citation: citation_renderings(item, ref, renderer,
                                          type: type,
                                          disambiguator:
                                            disambiguators[item.id]),
            formattedref: terminate_reference(ref, item),
          }
        end
      end

      # isodoc's styled citations consume these keys: the default is the
      # authoritative identifier; the short cite is the style's citation,
      # falling back to the reference rendering (the 1.x short-cite)
      FIRST_DELIM = '<span class="fmt-first-biblio-delim"/>'

      # A creator list alone (flavors' document-history name forms)
      def creator_names(item)
        @renderer.render_creators(to_model(item))
      end

      # render_all feeds the bibliography list: a reference not ending
      # in the biblio terminator takes one (the 1.x render1 behaviour;
      # single-item render stays verbatim)
      # The batch disambiguation suffixes ("2022a"): items sharing a
      # principal-creator surname and a date take alphabetical
      # suffixes in bibliography order (the 1.x
      # disambig_author_date_citations)
      def date_disambiguators(items)
        keys = items.filter_map do |item|
          begin
            [item.id, @renderer.author_key(item),
             @renderer.citation(item)]
          rescue ::Relaton::Render::Unrenderable
            nil
          end
        end
        groups = keys.group_by { |_, author, cite| [author, cite] }
        suffixes = {}
        groups.each_value do |group|
          next if group.size < 2

          group.each_with_index do |(id, _author, _cite), i|
            suffixes[id] = ("a".ord + i).chr
          end
        end
        suffixes
      end

      # The bibliography terminator; flavors override to suppress it
      # (1.x use_terminator?), receiving the item it terminates. A
      # reference closing on a footnote closes the sentence before it:
      # the terminator lands ahead of the trailing fn.
      FOOTNOTE_CLOSE = "</fn>".freeze

      def terminate_reference(ref, _item = nil)
        return ref if ref.empty? || ref.rstrip.end_with?(".")

        if (fn = ref.rindex("<fn"))
          head = ref[0...fn].rstrip
          return ref if head.empty?

          sep = head.end_with?(".") ? "" : "."
          return "#{head}#{sep}#{ref[fn..]}"
        end

        "#{ref}."
      end

      # The style-keyed capsule ("citation" => { author_date: "..." })
      # is what isodoc's styled erefs consume (their style attribute
      # names the key)
      def citation_renderings(item, ref, renderer, type: "author-date",
                              disambiguator: nil)
        # A style declaring shortFromReference takes the reference form
        # with the first-biblio marker (the 1.x citetemplate short)
        short = if renderer.short_from_reference?
                  renderer.render_short(item, FIRST_DELIM)
                else
                  short = renderer.citation(item)
                  short.empty? ? renderer.render_short(item, FIRST_DELIM) :
                    short
                end

        title = renderer.title_citation(item)

        {
          full: ref,
          default: item.docidentifier.first&.content.to_s,
          short: short,
          author_date: renderer.citation(item,
                                         disambiguator: disambiguator),
          author_date_br: renderer.bracketed_date_citation(
            item, disambiguator: disambiguator,
          ),
          author: renderer.in_text_author(item),
          date: renderer.disambiguated_date(item),
          # reference_tag: no rendering — isodoc falls back to the
          # biblio-tag anchor (the 1.x nil)
          title: title,
          title_reference_tag: title,
        }
      end

      # isodoc's pref_ref_code_parse reads
      # data[:authoritative_identifier] to build biblio-tag identifiers
      # (presentation_function/docid.rb). Returns [data, self] as the
      # 1.x signature did.
      def parse(doc)
        [{ authoritative_identifier: facade_docids(doc) }, self]
      end

      def citetemplate
        CiteTemplate.new(CITE_STYLES.to_h { |s| [s, ""] })
      end

      private

      # 1.x accepted a <references> XML string (isodoc strips namespaces
      # before building it) or a ready array of models.
      def facade_bibitems(bib)
        case bib
        when Array then bib
        when String
          require "moxml"
          root = Moxml.parse(bib).root
          return nil unless root&.name == "references"

          klass = facade_bibitem_class
          root.xpath("./bibitem").filter_map { |b| klass.from_xml(b.to_xml) }
        end
      end

      def facade_bibitem_class
        Relaton::Bib::Bibitem
      rescue NameError
        Relaton::Bib::Item
      end

      # 1.x Parse#authoritative_identifier semantics: the
      # primary/language cascade, the excluded types (URN, DOI, ISBN...)
      # dropped, and scoped ids (biblio-tag duplicates, IEEE trademark)
      # demoted within their type group. isodoc hands the live bibitem
      # node with the document's default namespace still attached, so the
      # element queries must be namespace-agnostic.
      EXCLUDED_ID_TYPES = %w(METANORMA METANORMA-ORDINAL AUTHOR-DATE TITLE
                             URN ISO-REFERENCE ISSN ISBN DOI).freeze

      # Flavors extend the authoritative-identifier exclusions by
      # overriding this reader on their facade subclass
      def excluded_id_types
        EXCLUDED_ID_TYPES
      end

      def facade_docids(doc)
        node = doc
        unless node.respond_to?(:xpath)
          require "moxml"
          node = Moxml.parse(doc.to_s).root
        end
        return [] unless node

        ids = node.xpath("./*[local-name() = 'docidentifier']")
        ids = facade_scope_filter(ids)
        out = nil
        [
          ->(x) { x["language"] == @lang && x["primary"] },
          ->(x) { x["primary"] },
          ->(x) { x["language"] == @lang },
          ->(_x) { true },
        ].each do |p|
          out = ids.select do |x|
            p.call(x) && !excluded_id_types.include?(facade_id_type(x))
          end
          out.empty? or break
        end
        # esc-wrapped: isodoc's l10n skips the tags, leaving a standard
        # identifier's punctuation verbatim (the 1.x Parse behaviour)
        out.map { |x| "<esc>#{x.text.strip}</esc>" }
      end

      def facade_id_type(id)
        t = id["type"] or return nil
        m = /\A(ISBN|ISSN)\..*/i.match(t) or return t.upcase
        m[1].upcase
      end

      def facade_scope_filter(ids)
        ids.detect { |i| i["scope"] } or return ids
        ids.group_by { |i| i["type"] }.flat_map do |type, group|
          grouped = group.group_by { |i| i["scope"] }
          if type == "IEEE" then grouped["trademark"] || grouped[nil] || []
          else grouped[nil] || []
          end
        end
      end

      # 1.x accepted string- and symbol-keyed options alike (the old
      # engine deep-symbolized via metanorma-utils); isodoc's bibrenderer
      # and every flavor still pass string keys.
      def deep_symbolize(value)
        case value
        # isodoc i18n hashes carry nil keys (an unlabeled punct slot)
        when Hash then value.to_h { |k, v| [k&.to_sym, deep_symbolize(v)] }
        when Array then value.map { |v| deep_symbolize(v) }
        else value
        end
      end

      # 1.x render/citation accepted a bibitem XML string; the Iso690
      # engine consumes model instances.
      def to_model(model)
        return model unless model.is_a?(String)

        klass = facade_bibitem_class
        klass.from_xml(model)
      end

      def warn_general_config
        return if General.config_warned

        General.config_warned = true
        warn "relaton-render: Relaton::Render::General is a compatibility " \
             "facade over the v2 engine; the liquid config option is " \
             "retired and ignored. Author a CitationStyle instance " \
             "(relaton-models citation module) for custom rendering."
      end

      class << self
        attr_accessor :config_warned
      end
    end
  end
end
