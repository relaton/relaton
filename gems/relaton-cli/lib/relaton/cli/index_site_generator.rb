require "json"
require "yaml"
require "zlib"
require "pathname"
require "fileutils"
require "liquid"
require "relaton/cli/frontend_assets"
require "relaton/index"
require "zip"
require "pubid"
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
      STALE_GLOBS = ["search.json", "search-*.json", "detail-*.json", "index/*.json", "index-v*.yaml", "index-v*.zip"].freeze
      # Normalized key -> compact key. Order defines the key order in a shard
      # record; a key NOT listed here is a detail field (see #detail_record).
      COMPACT_KEYS = {
        "id" => "r", "title" => "c", "doctype" => "t", "stage" => "s",
        "date" => "d", "yaml" => "u", "link" => "l"
      }.freeze
      # flavor token -> [pubid namespace, relaton namespace], for the tokens
      # that do not follow the plain capitalize rule. 3GPP is the only one:
      # `Pubid::Tgpp` against `Relaton::ThreeGpp`.
      FLAVOR_NAMESPACES = {
        "3gpp" => %w[Tgpp ThreeGpp], "tgpp" => %w[Tgpp ThreeGpp]
      }.freeze
      # A monolith base name: one path segment, so `--index-name` can neither
      # write outside the output directory nor collide with a hidden file.
      INDEX_NAME = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
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

      # The machine-consumable index: docid -> file rows a data repo
      # publishes as index-vN.yaml, emitted on the Pages site as JSON
      # shards plus a monolith, per the contract documented in
      # relaton/relaton#113 (contract v2) and specified in
      # docs/data-repository-format.adoc.
      #
      # Every row is structured: each data repo publishes a pubid index, so
      # the generator always has a parser and never writes a plain-string id.
      # A row the parser rejects takes its id from the repo's committed index
      # (`committed:`), and is dropped only when that has no row for it either
      # — `Relaton::Index::FileIO#deserialize_id` rejects the *whole* index on
      # the first row it cannot deserialize, so one string row would poison
      # the file.
      #
      # Shard key: `crc32(pubid.root.number.to_s) % N` — the same expression
      # `Relaton::Index` bsearches on (`Type#candidates_by_number`,
      # `FileIO#deserialize_pubid`). A document family (base, parts,
      # amendments) shares one root and lands in one shard. The key is NOT
      # given a rendered-id fallback: that would break the identity, so a
      # client computing the key from its parsed query would look in a bucket
      # the row is not in and read the miss as not-found. An identifier with
      # no root number keys on "" and lands in shard 0.
      class MachineIndex
        TARGET_ROWS = 15
        MIN_ROWS = 2000
        MIN_SHARDS = 16
        MAX_SHARDS = 65_536

        # Deliberately does NOT retain the pubid object: `add` extracts the only
        # two things the write path needs (`key`, `id_hash`) while the document
        # streams past, then lets the identifier go. Retaining it costs 3.14 KB
        # per row against 0.44 KB for the derived values alone — 543 MB vs 76 MB
        # on a 177k-row corpus. Anything else derived from pubid must therefore
        # be computed in `add` too; by write time the object is gone.
        Row = Struct.new(:rendered, :file, :key, :id_hash)

        attr_reader :rows

        # @param pubid_class [Class] the flavor's pubid Identifier
        # @param index_name [String] the monolith's base name, from the
        #   flavor's `INDEXFILE`
        # @param committed [Hash, nil] `{ file => id hash }` read from the
        #   repo's own committed index, consulted only when a rendered docid
        #   does not parse
        def initialize(pubid_class:, index_name:, committed: nil)
          @pubid_class = pubid_class
          @index_name = index_name
          @committed = committed || {}
          @rows = []
        end

        def add(rendered, file)
          row = Row.new(rendered, file)
          # Precompute the expensive derived values (root.number walk,
          # lutaml to_hash) once during the streaming pass — computing
          # them at monolith-write time is pathological on 177k rows
          # because each involves object-graph traversal.
          pubid = parse(rendered)
          # A rendered docid the parser rejects falls back to the repo's own
          # committed row: the crawler resolved that id from source metadata.
          # The hash is kept verbatim, so the site's row is byte-identical to
          # the repo's. A row with neither keeps a nil id_hash, which
          # `indexed_rows` drops and `skipped_count` reports.
          hash = pubid ? pubid.to_hash : @committed[file]
          pubid ||= from_hash(hash)
          if pubid
            row.id_hash = hash
            row.key = key_string(pubid)
          end
          @rows << row
        end

        def count
          @rows.size
        end

        def key_strategy
          "root-number"
        end

        # Sized from the rows actually written, the same figure the manifest
        # reports as `count` — not from every row scanned.
        def shard_count
          written = indexed_rows.size
          return 0 if written < MIN_ROWS

          next_pow2((written.to_f / TARGET_ROWS).ceil).clamp(MIN_SHARDS, MAX_SHARDS)
        end

        def key_of(row)
          row.key
        end

        def manifest(generated:)
          {
            "version" => 2,
            # The monolith's base name, so a client can fetch
            # "#{index}.zip" without knowing the flavor's INDEXFILE.
            "index" => @index_name,
            # What the index actually contains, not what was scanned: rows
            # whose id could not be resolved at all are dropped.
            "count" => indexed_rows.size,
            "shards" => shard_count,
            "key" => key_strategy,
            "algorithm" => "crc32",
            "generated" => generated,
          }
        end

        # { "r" => rendered, "file" => path, "id" => pubid hash }. The same
        # "id" the monolith carries for that row — the two artifacts must not
        # describe one document differently.
        def row_record(row)
          { "r" => row.rendered, "file" => row.file, "id" => row.id_hash }
        end

        # The rows actually written, in deterministic (key, rendered) order.
        #
        # Carries only rows whose id resolved: the consumer
        # (`Relaton::Index::FileIO#deserialize_id`) calls `from_hash` on every
        # row and raises `InvalidIndexError` on the first one it cannot
        # deserialize, which rejects the *whole* index — so a single unresolved
        # row written as a plain string would poison the file. Five shipping
        # corpora carry a handful of ids that do not parse back from the
        # rendered string (ieee 69, itu-r 47, iec 42, itu 3, nist 3), so this is
        # reachable, not theoretical; `add` rescues those from the committed
        # index, and only what that misses is dropped.
        # `Relaton::Ieee::DataFetcher#build_index` already skips the same rows
        # for the same reason and logs the loss; this matches it.
        #
        # Memoized, and the single place the sort happens — `each_shard` and
        # `write_monolith` previously sorted the corpus independently, so both
        # ran on every build.
        def indexed_rows
          @indexed_rows ||= @rows.reject { |row| row.id_hash.nil? }
                                 .sort_by { |row| [row.key, row.rendered] }
        end

        # Rows dropped by `indexed_rows` — reported so the loss is never silent.
        def skipped_count
          count - indexed_rows.size
        end

        # Rows bucketed by shard, in deterministic (key, rendered) order;
        # empty buckets are absent — a client treats a 404 as not-found.
        def each_shard
          n = shard_count
          return enum_for(:each_shard) unless block_given? && n.positive?

          buckets = Array.new(n) { [] }
          indexed_rows.each { |row| buckets[Zlib.crc32(row.key) % n] << row_record(row) }
          buckets.each_with_index { |rows, i| yield(format("%05d", i), rows) unless rows.empty? }
        end

        def monolith_filename
          "#{@index_name}.yaml"
        end

        # Same shape Relaton::Index::FileIO#save emits: an Array of
        # {id:, file:} hashes, id always a pubid to_hash. Streamed one row at a
        # time — building the full array and calling to_yaml is
        # pathological on six-figure corpora (Psych re-allocates on
        # every nested hash, and the whole array sits in memory).
        # Hand-rolls the YAML instead of calling to_yaml per row:
        # Psych's per-invocation overhead on 177k rows takes ~40 min.
        # The shapes are flat (string id) or one-level-nested (pubid
        # to_hash), so hand-rendering is straightforward and the output
        # is indistinguishable from what Psych produces.
        def write_monolith(path)
          File.open(path, "w:utf-8") do |f|
            f << "---\n"
            indexed_rows.each do |row|
              f << "- :id:\n"
              yaml_nested(f, row.id_hash, "    ")
              f << "  :file: #{yaml_scalar(row.file)}\n"
            end
          end
        end

        # An Array is written as a JSON flow sequence, which is valid YAML and
        # escapes every element unambiguously. It must not reach `yaml_scalar`:
        # there `["IEC"].to_s` starts with "[", so it was quoted into the String
        # "[\"IEC\"]" — every ISO/IEC copublished id (`copublishers`) — and
        # `from_hash` cannot cast that, so `FileIO` rejects the whole index.
        def yaml_nested(f, hash, indent)
          hash.each do |k, v|
            case v
            when Hash
              f << "#{indent}#{k}:\n"
              yaml_nested(f, v, indent + "  ")
            when Array
              f << "#{indent}#{k}: #{JSON.generate(v)}\n"
            else
              f << "#{indent}#{k}: #{yaml_scalar(v)}\n"
            end
          end
        end

        # YAML 1.1 plain scalars Psych resolves to true/false/nil. Emitted bare,
        # an id or path with one of these literal values changes *type* on the
        # round trip ("yes" -> true, "null" -> nil).
        YAML11_PLAIN = /\A(?:y|Y|yes|Yes|YES|n|N|no|No|NO|true|True|TRUE|
                           false|False|FALSE|on|On|ON|off|Off|OFF|
                           null|Null|NULL|~)\z/x

        def yaml_scalar(value)
          # Booleans and numbers are emitted bare, so they keep their type.
          # Quoting them is what the String branch below exists to prevent,
          # inverted: a pubid `to_hash` carrying a real `true` (CIE's
          # `d_prefix`, 31 of its 1139 rows) came back as the String "true", and
          # the published row no longer matched the repo's own index.
          return "" if value.nil?
          return value.to_s if value == true || value == false || value.is_a?(Integer)

          s = value.to_s
          # Quote if the value could be ambiguous: leading special char, an
          # embedded ": " or " #", numeric-looking, *trailing* whitespace (the
          # guard here used to read /\z\s/, which can never match — nothing
          # follows end-of-string), a YAML 1.1 plain word, or a C0 control
          # character. The control case is the severe one: emitted raw it makes
          # the whole file unparseable, and one bad row rejects the entire index.
          if s.empty? ||
             s.match?(/\A[-?:,\[\]{}#&*!|>'"%@`\s]|:\s|\s#|\A\d|\s\z/) ||
             s.match?(YAML11_PLAIN) || s.match?(/[[:cntrl:]]/)
            s.inspect
          else
            s
          end
        end



        private

        def next_pow2(value)
          bit = 0
          bit += 1 while (1 << bit) < value
          1 << bit
        end

        def parse(rendered)
          @pubid_class.parse(rendered)
        rescue StandardError
          nil
        end

        # Only a structured hash: a legacy index under the same name carries
        # plain strings, and one written into a row would break the monolith
        # (`yaml_nested` walks a Hash) and the consumer alike.
        def from_hash(hash)
          hash.is_a?(Hash) && @pubid_class.from_hash(hash) || nil
        rescue StandardError
          nil
        end

        # The narrowing key `Relaton::Index` sorts and bsearches on. An
        # identifier with no root number gives "", so those rows cluster in
        # shard 0 — the same degeneracy the gem's bsearch already has, and the
        # only shape a client can reproduce without knowing our fallbacks.
        def key_string(pubid)
          pubid.root.number.to_s
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
        @emit_index = options.fetch(:machine_index, true)
        @publish_data = options.fetch(:publish_data, false)
        @pubid_class = pubid_class_for(options[:flavor])
        @index_name = index_name_for(options[:flavor])
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
        counts[:index_shards] = write_machine_index_manifest(counts[:total]) if emit_index?
        publish_data! if @publish_data

        index_path = File.join(output, "index.html")
        write_file(index_path, render(assets, counts))
        copy_404_fallback
        Util.info "Indexed #{counts[:total]} document(s) from #{sources_description} " \
                  "into #{counts[:shards]} search shard(s), " \
                  "#{counts[:detail_shards]} detail shard(s) and " \
                  "#{counts[:index_shards]} machine-index shard(s)"
        index_path
      end

      private

      attr_reader :data_dir, :options, :output, :lang, :overwrite, :base_url,
                  :title, :description, :favicon, :generated, :include_static,
                  :shard_size, :detail_shard_size

      def emit_detail?
        @emit_detail
      end

      # `flavor` names the flavor ("iso", "iho", ...) whose pubid Identifier
      # parses docids and whose `INDEXFILE` names the published monolith.
      # Resolved from the two gems' own namespaces — the alias table carries
      # only the names that do not follow the capitalize rule.
      def pubid_class_for(flavor)
        return nil unless flavor_key(flavor)

        name = namespace_names(flavor).first
        ::Pubid.const_get(name).const_get(:Identifier)
      rescue NameError => e
        raise unless probed_constant?(e, name, :Identifier)

        raise ArgumentError, "unknown pubid flavor: #{flavor}"
      end

      # The monolith's base name. Derived from the flavor's own `INDEXFILE`
      # so the site publishes the file that flavor's consumer already fetches
      # — the version there encodes the index *structure*, per flavor, and is
      # not a global generation counter. `index_name:` overrides it for a
      # corpus that is not a relaton flavor.
      def index_name_for(flavor)
        override = presence(options[:index_name])
        return override if override
        return nil unless flavor_key(flavor)

        name = namespace_names(flavor).last
        ::Relaton.const_get(name).const_get(:INDEXFILE)
      rescue NameError => e
        raise unless probed_constant?(e, name, :INDEXFILE)

        raise ArgumentError,
              "no relaton flavor for `#{flavor}`; pass index_name to name the index"
      end

      # True only when the NameError is about the constant we looked up. Looking
      # it up runs the flavor's autoload, and a genuine NameError from inside
      # that file must surface as itself — relabelled "unknown flavor", it
      # would send whoever reads a red deploy to --index-name instead of the bug.
      def probed_constant?(error, *names)
        names.map(&:to_s).include?(error.name.to_s)
      end

      def flavor_key(flavor)
        key = flavor.to_s.strip.downcase
        key unless key.empty?
      end

      # [pubid namespace, relaton namespace] for a flavor token. They agree for
      # every flavor but 3GPP, whose pubid namespace is Tgpp.
      def namespace_names(flavor)
        key = flavor_key(flavor)
        FLAVOR_NAMESPACES.fetch(key) do
          name = key.split(/[_-]/).map(&:capitalize).join
          [name, name]
        end
      end

      def emit_index?
        @emit_index
      end

      # The data folder's parent — the repo root the index rows' `file` paths
      # and the committed index are relative to.
      def repo_root
        @repo_root ||= File.dirname(File.expand_path(data_dir))
      end

      # `{ file => id hash }` from the repo's own committed index, the
      # authority for a docid the parser cannot read back from its rendered
      # form. Empty when the repo publishes no index (a fresh repo, or one
      # whose index this build is the first to produce).
      def committed_index
        return @committed_index if defined?(@committed_index)

        path = File.join(repo_root, "#{@index_name}.yaml")
        @committed_index = File.exist?(path) ? read_committed_index(path) : {}
      rescue StandardError => e
        Util.warn "Ignoring #{path}: #{e.message}"
        @committed_index = {}
      end

      # Keeps only rows whose `:id` is a structured hash. A legacy index under
      # the same name carries plain strings, and one of those written into a
      # row would break both the monolith (`yaml_nested` walks a Hash) and the
      # consumer (`FileIO#deserialize_id` calls `from_hash`).
      def read_committed_index(path)
        rows = YAML.safe_load(File.read(path), permitted_classes: [Symbol])
        Array(rows).each_with_object({}) do |row, acc|
          next unless row.is_a?(Hash) && row[:id].is_a?(Hash)

          acc[row[:file]] = row[:id]
        end
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

        # Every data repo publishes a pubid index, so a machine index without
        # a parser could only carry plain-string ids — a shape no consumer
        # narrows on and this generator no longer writes.
        return unless emit_index?

        if @pubid_class.nil?
          raise ArgumentError,
                "--pubid-flavor is required to build a machine index; " \
                "pass --no-machine-index to build the human site only"
        end
        return if @index_name.match?(INDEX_NAME)

        raise ArgumentError,
              "index name must be a single file name such as index-v2 (got #{@index_name.inspect})"
      end

      # Human-readable description of the folders scanned, for the info log.
      # Keeps data_dir as given (no absolute-path noise) and only notes when a
      # sibling static/ was folded in.
      def sources_description
        repo_root = self.repo_root
        static_source_dir(repo_root) ? "#{data_dir} (+ #{STATIC_DIRNAME}/)" : data_dir
      end

      # ---- streaming ----------------------------------------------------------

      # The machine-index input: rendered primary docid + repo-relative
      # path (clients prefix their own baseurl onto file).
      def machine_record(item)
        [item["id"], item["yaml_path"]]
      end

      def write_machine_index_manifest(total)
        machine = @machine_index or return 0

        FileUtils.mkdir_p(File.join(output, "index"))
        machine.each_shard do |number, rows|
          write_file(File.join(output, "index", "shard-#{number}.json"), JSON.generate(rows))
        end

        monolith = File.join(output, machine.monolith_filename)
        machine.write_monolith(monolith)
        zip_file(monolith)

        write_file(
          File.join(output, "index", "manifest.json"),
          JSON.pretty_generate(machine.manifest(generated: @generated)),
        )
        if machine.skipped_count.positive?
          Util.warn "Machine index: skipped #{machine.skipped_count} of " \
                    "#{machine.count} document(s) whose id could not be parsed " \
                    "(a structured index cannot carry them)."
        end
        machine.shard_count
      end

      # Zip sibling of a monolith — the form `Relaton::Index url:`
      # fetches today. The zip stores the yaml at its bare basename,
      # matching the layout data repos publish in git.
      def zip_file(yaml_path)
        zip_path = yaml_path.sub(/\.yaml\z/, ".zip")
        File.delete(zip_path) if File.exist?(zip_path)
        Zip::File.open(zip_path, create: true) do |archive|
          archive.add(File.basename(yaml_path), yaml_path)
        end
      end

      # Copy the scanned corpus onto the site so clients can fetch
      # documents (the index rows' `file` paths) from the same origin.
      # Opt-in: for most repos raw.githubusercontent already serves the
      # committed data, and duplicating a large corpus would double the
      # published-site size against the 1 GB cap.
      def publish_data!
        repo_root = self.repo_root
        source_dirs(repo_root).each do |dir|
          Dir.glob(File.join(dir, "**", "*.{yaml,yml}")).sort.each do |src|
            # Relative to the data dir itself, so the copy lives at
            # output/data/<name>.yaml matching the index rows' file paths.
            rel = Pathname.new(File.expand_path(src))
                      .relative_path_from(Pathname.new(dir)).to_s
            dest = File.join(output, "data", rel)
            FileUtils.mkdir_p(File.dirname(dest))
            FileUtils.cp(src, dest)
          end
        end
      end

      # One pass over the corpus, fanning each document out to both shard
      # families. The search/detail families accumulate nothing — peak memory is
      # one shard of each. The machine index is the exception: shard assignment
      # needs the corpus size, which is not knowable until the pass ends, so
      # `MachineIndex` retains one `Row` per document (measured ~0.44 KB/row — 76 MB at 177k
      # rows; see the note on `Row`, which is why it does not hold the pubid).
      def write_shards
        writer = method(:write_file)
        summary = ShardWriter.new(output, SHARD_PATTERN, shard_size, &writer)
        detail = ShardWriter.new(output, DETAIL_PATTERN, detail_shard_size, &writer)
        if emit_index?
          machine = MachineIndex.new(pubid_class: @pubid_class,
                                     index_name: @index_name,
                                     committed: committed_index)
        end
        total = 0

        each_document do |doc|
          total += 1
          summary << compact_record(doc)
          detail << detail_record(doc) if emit_detail?
          machine&.add(*machine_record(doc))
        end
        summary.flush
        detail.flush
        @machine_index = machine

        { total: total, shards: summary.count, detail_shards: detail.count }
      end

      # Yield each index item in corpus order. De-dup is **cross-dir only**: an id
      # already indexed from an *earlier* dir (i.e. static/ duplicating a data/
      # doc) is skipped, so data/ wins — but duplicates *within* a single dir are
      # left as-is, preserving the pre-static behavior of the data scan.
      def each_document
        return to_enum(:each_document) unless block_given?

        repo_root = self.repo_root
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
            # The machine index needs the repo-relative path: clients
            # prefix their own baseurl onto row[:file], so an absolutized
            # ref (yaml_ref with --base-url) would double-prefix.
            item["yaml_path"] = relative_path(file, repo_root)
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
        # "yaml_path" is transport for the machine index, not a detail field.
        rest = item.reject { |key, _| COMPACT_KEYS.key?(key) || key == "yaml_path" }
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
      # Path-based document URLs (/doc/<id>) are served by this fallback:
      # GitHub Pages has no rewrites, so unknown paths resolve to 404.html,
      # whose script forwards the id into the app as ?doc=<id>.
      def copy_404_fallback
        fallback = File.join(FrontendAssets.dist_dir, "404.html")
        return unless File.exist?(fallback)

        write_file(File.join(output, "404.html"), File.read(fallback))
      end

      def purge_stale!
        return unless overwrite

        # Read before the glob deletes it. `--index-name` accepts a name
        # `index-v*` does not match, so the previous build's own manifest is
        # the only record of which monolith it wrote.
        previous = previous_index_name
        # `base:` rather than interpolating `output` into the pattern: an output
        # path containing glob metacharacters (`[`, `{`, `*`, `?`, …) would
        # otherwise match nothing, and the stale shards would survive silently.
        paths = Dir.glob(STALE_GLOBS, base: output).map { |name| File.join(output, name) }
        paths += %w[yaml zip].map { |ext| File.join(output, "#{previous}.#{ext}") } if previous
        paths.uniq.each { |path| File.delete(path) if File.file?(path) }
      end

      # The monolith name a previous build recorded, if it is a safe basename.
      def previous_index_name
        path = File.join(output, "index", "manifest.json")
        return unless File.file?(path)

        name = JSON.parse(File.read(path))["index"]
        name if name.is_a?(String) && name.match?(INDEX_NAME)
      rescue JSON::ParserError
        nil
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
