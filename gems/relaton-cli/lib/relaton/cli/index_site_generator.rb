require "json"
require "yaml"
require "pathname"
require "fileutils"
require "liquid"
require "relaton/cli/frontend_assets"
require "relaton/cli/index_item_normalizer"

module Relaton
  module Cli
    # Builds a browsable HTML index site from a folder of Relaton bibliographic
    # YAML documents (default ./data, arbitrarily nested).
    #
    # The page shell carries no document data at all — only branding, the
    # inlined Vue+Tailwind bundle, and the scalars describing the shard layout.
    # Documents are written as numbered JSON shards the frontend fetches:
    #
    #   search-NNNN.json  summary records {r,c,t,s,d,u,l}, loaded progressively
    #   detail-NNNN.json  the rich fields, fetched when a detail panel opens
    #
    # So page weight is a function of what the user looks at, not of corpus size,
    # and the generator streams rather than materializing the whole corpus.
    class IndexSiteGenerator
      TEMPLATE_DIR = File.expand_path("../../../templates/index", __dir__).freeze
      # index YAMLs that are machine indexes, not documents.
      SKIP_BASENAMES = /\Aindex(-v\d+)?\.ya?ml\z/i
      # Sibling of the data folder holding manually-curated bib docs (ISO/IEC
      # Directives, JCGM/GUM guides, NIST research-library metadata, …) that the
      # crawler can't fetch. Part of the corpus (referenced by index-vN.yaml), so
      # it belongs in the browsable site too.
      STATIC_DIRNAME = "static".freeze
      SHARD_PATTERN = "search-%04d.json".freeze
      DETAIL_PATTERN = "detail-%04d.json".freeze
      # Output written by a previous build that must not survive into this one:
      # a shrunken corpus would otherwise leave orphan shards nothing points at.
      STALE_GLOBS = ["search.json", "search-*.json", "detail-*.json"].freeze
      # Normalized key -> compact key. Order defines the key order in a shard
      # record; a key NOT listed here is a detail field (see #detail_record).
      COMPACT_KEYS = {
        "id" => "r", "title" => "c", "doctype" => "t", "stage" => "s",
        "date" => "d", "yaml" => "u", "link" => "l"
      }.freeze
      # <link rel="icon"> type hints, keyed by the favicon href's extension. An
      # unlisted extension emits no type at all and lets the browser sniff.
      FAVICON_TYPES = {
        ".svg" => "image/svg+xml", ".png" => "image/png", ".ico" => "image/x-icon",
        ".gif" => "image/gif", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg"
      }.freeze

      # Buffers records and flushes them as `dir/<pattern % n>` shards of at most
      # `size` records, so peak memory is O(size), not O(corpus). Writing is
      # delegated so the caller keeps control of the overwrite policy.
      class ShardWriter
        attr_reader :count

        def initialize(dir, pattern, size, &write)
          @dir = dir
          @pattern = pattern
          @size = size
          @write = write
          @buffer = []
          @count = 0
        end

        def <<(record)
          @buffer << record
          flush if @buffer.size >= @size
          self
        end

        # No-op on an empty buffer, so an exact multiple of `size` doesn't emit a
        # trailing empty shard and an empty corpus emits none at all.
        def flush
          return if @buffer.empty?

          @write.call(File.join(@dir, format(@pattern, @count)), JSON.generate(@buffer))
          @count += 1
          @buffer.clear
        end
      end

      # @param data_dir [String]
      # @param options [Hash] :output :title :description :favicon :base_url
      #   :overwrite :lang :generated :static :shard_size :detail_shard_size
      #   :detail
      def self.generate(data_dir, options = {})
        new(data_dir, options).generate
      end

      def initialize(data_dir, options = {})
        @data_dir = data_dir
        @options = options
        @output = options[:output] || "_site"
        @lang = options[:lang] || "en"
        @overwrite = options.fetch(:overwrite, true)
        @base_url = options[:base_url]
        @title = presence(options[:title]) || "Relaton Index"
        @description = presence(options[:description])
        @favicon = presence(options[:favicon])
        @generated = options.fetch(:generated) { Time.now.utc.strftime("%Y-%m-%d") }
        @include_static = options.fetch(:static, true)
        @shard_size = options.fetch(:shard_size, 5000)
        @detail_shard_size = options.fetch(:detail_shard_size, 500)
        @emit_detail = options.fetch(:detail, true)
        validate!
      end

      # @return [String] path to the written index.html
      def generate
        # Read the bundle first: a missing frontend build must fail before any
        # output is written, not halfway through a corpus.
        assets = { "css" => FrontendAssets.stylesheet, "iife" => FrontendAssets.iife }

        FileUtils.mkdir_p(output)
        purge_stale!
        counts = write_shards

        index_path = File.join(output, "index.html")
        write_file(index_path, render(assets, counts))
        Util.info "Indexed #{counts[:total]} document(s) from #{sources_description} " \
                  "into #{counts[:shards]} search shard(s) and " \
                  "#{counts[:detail_shards]} detail shard(s)"
        index_path
      end

      private

      attr_reader :data_dir, :options, :output, :lang, :overwrite, :base_url,
                  :title, :description, :favicon, :generated, :include_static,
                  :shard_size, :detail_shard_size

      def emit_detail?
        @emit_detail
      end

      # nil for a nil/blank option value. A caller workflow that forwards an
      # unset input renders it as an empty string (`--favicon ""`), which must
      # mean "not set" — an empty href in <link rel="icon"> resolves to the page
      # itself, and an empty <meta name="description"> is worse than none.
      def presence(value)
        str = value.to_s.strip
        str unless str.empty?
      end

      def validate!
        if options.key?(:mode)
          raise ArgumentError,
                "The `mode` option was removed: `relaton index` now always emits " \
                "sharded JSON that the page fetches. Drop --mode from the call."
        end
        unless File.directory?(data_dir)
          raise ArgumentError, "Data directory not found: #{data_dir}"
        end

        { shard_size: shard_size, detail_shard_size: detail_shard_size }
          .each do |name, value|
            next if value.is_a?(Integer) && value.positive?

            raise ArgumentError, "#{name} must be a positive integer (got #{value.inspect})"
          end
      end

      # Human-readable description of the folders scanned, for the info log.
      # Keeps data_dir as given (no absolute-path noise) and only notes when a
      # sibling static/ was folded in.
      def sources_description
        repo_root = File.dirname(File.expand_path(data_dir))
        static_source_dir(repo_root) ? "#{data_dir} (+ #{STATIC_DIRNAME}/)" : data_dir
      end

      # ---- streaming ----------------------------------------------------------

      # One pass over the corpus, fanning each document out to both shard
      # families. Nothing accumulates: peak memory is one shard of each kind.
      def write_shards
        writer = method(:write_file)
        summary = ShardWriter.new(output, SHARD_PATTERN, shard_size, &writer)
        detail = ShardWriter.new(output, DETAIL_PATTERN, detail_shard_size, &writer)
        total = 0

        each_document do |doc|
          total += 1
          summary << compact_record(doc)
          detail << detail_record(doc) if emit_detail?
        end
        summary.flush
        detail.flush

        { total: total, shards: summary.count, detail_shards: detail.count }
      end

      # Yield each index item in corpus order. De-dup is **cross-dir only**: an id
      # already indexed from an *earlier* dir (i.e. static/ duplicating a data/
      # doc) is skipped, so data/ wins — but duplicates *within* a single dir are
      # left as-is, preserving the pre-static behavior of the data scan.
      def each_document
        return to_enum(:each_document) unless block_given?

        repo_root = File.dirname(File.expand_path(data_dir))
        seen = {}
        source_dirs(repo_root).each do |dir|
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
            yield item
          end
          seen.merge!(dir_ids)
        end
      end

      # The compact summary record the search shards carry.
      def compact_record(item)
        COMPACT_KEYS.each_with_object({}) { |(key, short), acc| acc[short] = item[key] }
      end

      # The complement: everything the summary record doesn't carry, tagged with
      # the id so the frontend can verify a positional lookup landed on the right
      # record. nil when the document has no detail fields at all — the slot is
      # still written (as null) so position stays aligned with the summary shards.
      def detail_record(item)
        rest = item.reject { |key, _| COMPACT_KEYS.key?(key) }
        return nil if rest.empty?

        { "r" => item["id"] }.merge(rest)
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

      def render(assets, counts)
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
          "css" => assets["css"],
          "iife" => assets["iife"],
          "generated" => generated,
          "total" => counts[:total],
          "shards" => counts[:shards],
          "shard_size" => shard_size,
          "detail_shards" => counts[:detail_shards],
          "detail_shard_size" => detail_shard_size,
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

      # Drop shards from a previous build. Without a manifest, an orphan shard
      # left by a larger corpus is invisible — nothing points at it — so it would
      # sit in the deployed site indefinitely.
      def purge_stale!
        return unless overwrite

        # `base:` rather than interpolating `output` into the pattern: an output
        # path containing glob metacharacters (`[`, `{`, `*`, `?`, …) would
        # otherwise match nothing, and the stale shards would survive silently.
        Dir.glob(STALE_GLOBS, base: output).each do |name|
          path = File.join(output, name)
          File.delete(path) if File.file?(path)
        end
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
