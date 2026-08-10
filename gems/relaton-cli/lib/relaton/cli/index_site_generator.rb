require "json"
require "yaml"
require "pathname"
require "fileutils"
require "liquid"
require "relaton/cli/frontend_assets"
require "relaton/cli/index_item_normalizer"

module Relaton
  module Cli
    # Builds a browsable, self-contained HTML index site from a folder of Relaton
    # bibliographic YAML documents (default ./data, arbitrarily nested). The page
    # inlines the compiled Vue+Tailwind IIFE shipped in the gem and feeds it the
    # document data in one of three modes:
    #
    #   :embedded    crawler-indexable DOM + window.RELATON_INDEX_DATA JSON (default)
    #   :dom         crawler-indexable DOM only (frontend reads data-* attributes)
    #   :static-json search.json sidecar the frontend fetch()es (not crawlable)
    #
    # Output: <output>/index.html (+ <output>/search.json).
    class IndexSiteGenerator
      TEMPLATE_DIR = File.expand_path("../../../templates/index", __dir__).freeze
      MODES = %w[embedded dom static-json].freeze
      # index YAMLs that are machine indexes, not documents.
      SKIP_BASENAMES = /\Aindex(-v\d+)?\.ya?ml\z/i
      # Sibling of the data folder holding manually-curated bib docs (ISO/IEC
      # Directives, JCGM/GUM guides, NIST research-library metadata, …) that the
      # crawler can't fetch. Part of the corpus (referenced by index-vN.yaml), so
      # it belongs in the browsable site too.
      STATIC_DIRNAME = "static".freeze
      # <link rel="icon"> type hints, keyed by the favicon href's extension. An
      # unlisted extension emits no type at all and lets the browser sniff.
      FAVICON_TYPES = {
        ".svg" => "image/svg+xml", ".png" => "image/png", ".ico" => "image/x-icon",
        ".gif" => "image/gif", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg"
      }.freeze

      # @param data_dir [String]
      # @param options [Hash] :output :title :description :favicon :base_url
      #   :mode :overwrite :lang :generated :static
      def self.generate(data_dir, options = {})
        new(data_dir, options).generate
      end

      def initialize(data_dir, options = {})
        @data_dir = data_dir
        @options = options
        @output = options[:output] || "_site"
        @mode = (options[:mode] || "embedded").to_s
        @lang = options[:lang] || "en"
        @overwrite = options.fetch(:overwrite, true)
        @base_url = options[:base_url]
        @title = presence(options[:title]) || "Relaton Index"
        @description = presence(options[:description])
        @favicon = presence(options[:favicon])
        @generated = options.fetch(:generated) { Time.now.utc.strftime("%Y-%m-%d") }
        @include_static = options.fetch(:static, true)
        validate!
      end

      # @return [String] path to the written index.html
      def generate
        documents = collect_documents
        Util.info "Indexed #{documents.size} document(s) from " \
                  "#{sources_description}"

        FileUtils.mkdir_p(output)
        write_file(File.join(output, "search.json"), search_json(documents))
        index_path = File.join(output, "index.html")
        write_file(index_path, render(documents))
        index_path
      end

      private

      attr_reader :data_dir, :options, :output, :mode, :lang, :overwrite,
                  :base_url, :title, :description, :favicon, :generated,
                  :include_static

      # nil for a nil/blank option value. A caller workflow that forwards an
      # unset input renders it as an empty string (`--favicon ""`), which must
      # mean "not set" — an empty href in <link rel="icon"> resolves to the page
      # itself, and an empty <meta name="description"> is worse than none.
      def presence(value)
        str = value.to_s.strip
        str unless str.empty?
      end

      def validate!
        unless MODES.include?(mode)
          raise ArgumentError, "Unknown mode #{mode.inspect} (expected one of #{MODES.join(', ')})"
        end
        unless File.directory?(data_dir)
          raise ArgumentError, "Data directory not found: #{data_dir}"
        end
      end

      # Human-readable description of the folders scanned, for the info log.
      # Keeps data_dir as given (no absolute-path noise) and only notes when a
      # sibling static/ was folded in.
      def sources_description
        repo_root = File.dirname(File.expand_path(data_dir))
        static_source_dir(repo_root) ? "#{data_dir} (+ #{STATIC_DIRNAME}/)" : data_dir
      end

      # Collect index items from every source dir. De-dup is **cross-dir only**:
      # an id already indexed from an *earlier* dir (i.e. static/ duplicating a
      # data/ doc) is skipped, so data/ wins — but duplicates *within* a single
      # dir are left as-is, preserving the pre-static behavior of the data scan.
      def collect_documents
        repo_root = File.dirname(File.expand_path(data_dir))
        seen = {}
        source_dirs(repo_root).each_with_object([]) do |dir, acc|
          dir_ids = {}
          Dir.glob(File.join(dir, "**", "*.{yaml,yml}")).sort.each do |file|
            item = index_file(file, repo_root)
            next unless item

            id = dedup_key(item)
            if id && seen.key?(id)
              Util.warn "Skipping #{item['yaml']} (duplicate id #{id}); " \
                        "already indexed from #{seen[id]}"
              next
            end
            dir_ids[id] ||= item["yaml"] if id
            acc << item
          end
          seen.merge!(dir_ids)
        end
      end

      # The data folder, plus an auto-detected sibling static/ folder (its bib
      # docs are part of the corpus). Data is scanned first so it wins on a
      # cross-dir duplicate id. Enabled by default; --no-static opts out.
      def source_dirs(repo_root)
        [data_dir, static_source_dir(repo_root)].compact
      end

      # The sibling static/ dir to fold in, or nil when disabled, absent, or the
      # same folder as data_dir (guards `relaton index static` double-scanning).
      def static_source_dir(repo_root)
        return nil unless include_static

        static = File.join(repo_root, STATIC_DIRNAME)
        return nil unless File.directory?(static)
        return nil if File.expand_path(static) == File.expand_path(data_dir)

        static
      end

      # The id we de-dup on, or nil when the doc has no usable id (a blank/empty
      # id must NOT collapse distinct docid-less documents together).
      def dedup_key(item)
        id = item["id"]
        id unless id.nil? || id.empty?
      end

      # Normalize one YAML file to an index item, or nil if it's a machine index,
      # not a document, or unparseable.
      def index_file(file, repo_root)
        return if File.basename(file).match?(SKIP_BASENAMES)

        doc = load_yaml(file)
        return unless document?(doc)

        rel = relative_path(file, repo_root)
        IndexItemNormalizer.normalize(doc, lang: lang, yaml_ref: yaml_ref(rel))
      rescue Psych::SyntaxError => e
        Util.warn "Skipping #{file}: #{e.message}"
        nil
      end

      def load_yaml(file)
        content = File.read(file, encoding: "utf-8")
        begin
          YAML.safe_load(content, permitted_classes: [Date, Time], aliases: true)
        rescue ArgumentError
          # older Psych positional signature
          YAML.safe_load(content, [Date, Time], [], true)
        end
      end

      # A bib document (not a collection/index) — has an id/docid/title, no "root".
      def document?(doc)
        return false unless doc.is_a?(Hash)
        return false if doc.key?("root")

        doc.key?("id") || doc.key?("docidentifier") || doc.key?("title")
      end

      def relative_path(file, repo_root)
        Pathname.new(File.expand_path(file))
                .relative_path_from(Pathname.new(repo_root)).to_s
      end

      def yaml_ref(rel)
        return rel if base_url.nil? || base_url.empty?

        "#{base_url.chomp('/')}/#{rel}"
      end

      # ---- rendering ----------------------------------------------------------

      def render(documents)
        env = Liquid::Environment.build(
          file_system: Liquid::LocalFileSystem.new(TEMPLATE_DIR),
        )
        template = Liquid::Template.parse(
          File.read(File.join(TEMPLATE_DIR, "page.liquid"), encoding: "utf-8"),
          environment: env,
        )
        template.render!(
          "title" => title,
          "description" => description,
          "favicon" => favicon,
          "favicon_type" => favicon_type,
          "css" => FrontendAssets.stylesheet,
          "iife" => FrontendAssets.iife,
          "mode" => mode,
          "generated" => generated,
          "json_url" => "search.json",
          "data_json" => embed_json(documents),
          "documents" => documents,
        )
      end

      # The <link rel="icon"> type for the configured favicon, or nil when there
      # is none or its extension isn't a known image type. The href is passed
      # through verbatim (absolute URL or output-relative path alike), so any
      # ?query/#fragment is stripped before looking at the extension.
      def favicon_type
        return nil unless favicon

        FAVICON_TYPES[File.extname(favicon.split(/[?#]/, 2).first.to_s).downcase]
      end

      # Embedded JSON payload for window.RELATON_INDEX_DATA. Escaped so it can
      # never break out of the surrounding <script> tag. The description key is
      # omitted when unset, keeping the payload byte-identical for sites that
      # don't pass one.
      def embed_json(documents)
        return "null" if mode == "static-json"

        payload = { "title" => title }
        payload["description"] = description if description
        payload["generated"] = generated
        payload["documents"] = documents
        script_escape(JSON.generate(payload))
      end

      def search_json(documents)
        rows = documents.map do |d|
          { "r" => d["id"], "c" => d["title"], "t" => d["doctype"],
            "s" => d["stage"], "d" => d["date"], "u" => d["yaml"], "l" => d["link"] }
        end
        JSON.generate(rows)
      end

      # Make a JSON string safe to inline inside a <script> element: prevent a
      # literal "</script>" from closing the tag, and escape the U+2028/U+2029
      # line separators that are invalid in ECMAScript string literals.
      def script_escape(json)
        json.gsub("</", "<\\/")
            .gsub("\u2028", "\\u2028")
            .gsub("\u2029", "\\u2029")
      end

      def write_file(path, content)
        if File.exist?(path) && !overwrite
          Util.warn "Skipping existing #{path} (use --overwrite)"
          return
        end
        File.write(path, content, encoding: "utf-8")
      end
    end
  end
end
