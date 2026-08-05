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

      # @param data_dir [String]
      # @param options [Hash] :output :title :base_url :mode :overwrite :lang :generated
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
        @title = options[:title] || "Relaton Index"
        @generated = options.fetch(:generated) { Time.now.utc.strftime("%Y-%m-%d") }
        validate!
      end

      # @return [String] path to the written index.html
      def generate
        documents = collect_documents
        Util.info "Indexed #{documents.size} document(s) from #{data_dir}"

        FileUtils.mkdir_p(output)
        write_file(File.join(output, "search.json"), search_json(documents))
        index_path = File.join(output, "index.html")
        write_file(index_path, render(documents))
        index_path
      end

      private

      attr_reader :data_dir, :options, :output, :mode, :lang, :overwrite,
                  :base_url, :title, :generated

      def validate!
        unless MODES.include?(mode)
          raise ArgumentError, "Unknown mode #{mode.inspect} (expected one of #{MODES.join(', ')})"
        end
        unless File.directory?(data_dir)
          raise ArgumentError, "Data directory not found: #{data_dir}"
        end
      end

      def collect_documents
        repo_root = File.dirname(File.expand_path(data_dir))
        files = Dir.glob(File.join(data_dir, "**", "*.{yaml,yml}")).sort
        files.each_with_object([]) do |file, acc|
          next if File.basename(file).match?(SKIP_BASENAMES)

          doc = load_yaml(file)
          next unless document?(doc)

          rel = relative_path(file, repo_root)
          acc << IndexItemNormalizer.normalize(doc, lang: lang, yaml_ref: yaml_ref(rel))
        rescue Psych::SyntaxError => e
          Util.warn "Skipping #{file}: #{e.message}"
        end
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
          "css" => FrontendAssets.stylesheet,
          "iife" => FrontendAssets.iife,
          "mode" => mode,
          "generated" => generated,
          "json_url" => "search.json",
          "data_json" => embed_json(documents),
          "documents" => documents,
        )
      end

      # Embedded JSON payload for window.RELATON_INDEX_DATA. Escaped so it can
      # never break out of the surrounding <script> tag.
      def embed_json(documents)
        return "null" if mode == "static-json"

        script_escape(JSON.generate("title" => title,
                                    "generated" => generated,
                                    "documents" => documents))
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
