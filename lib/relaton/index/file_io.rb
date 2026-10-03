module Relaton
  module Index
    #
    # File IO class is used to read and write index files.
    # In searh mode url is used to fetch index from external repository and save it to storage.
    # In index mode url should be nil.
    #
    class FileIO
      # Raised internally when a deserialized id cannot be parsed or is not
      # understood by the pubid class; `#load_index` rescues it to trigger the
      # wrong-structure handling (re-download, or stop and log).
      class InvalidIndexError < StandardError; end

      # Bump when the sidecar payload shape changes, so an older sidecar is
      # discarded and rebuilt instead of misread.
      SIDECAR_VERSION = 2 # v2: the payload carries the yaml byte-size for freshness

      attr_reader :url, :pubid_class
      attr_accessor :sorted

      @@file_locks = {}
      @@file_locks_mutex = Mutex.new

      #
      # Initialize FileIO
      #
      # @param [String] dir falvor specific local directory in ~/.relaton to store index
      # @param [String, Boolean, nil] url
      #   if String then the URL is used to fetch an index from a Git repository
      #     and save it to the storage (if not exists, or older than 24 hours)
      #   if true then the index is read from the storage (used to remove index file)
      #   if nil then the fiename is used to read and write file (used to create indes in GH actions)
      # @param [Pubid::Identifier] pubid class for deserialization
      #
      # The index format check round-trips each id through `pubid_class`;
      # index format is now validated by round-tripping a sample of ids through
      # the pubid class (see #check_serialization), which understands the pubid
      # v2 (lutaml) `_type` serialization that the old key-allowlist could not.
      def initialize(dir, url: nil, filename: nil, pubid_class: nil)
        @dir = dir
        @url = url
        @filename = filename
        @pubid_class = pubid_class
        @sorted = false
      end

      #
      # If url is String, check if index file exists and is not older than 24
      #   hours. If not, fetch index from external repository and save it to
      #   storage.
      # If url is true, read index from path to local file.
      # If url is nil, read index from filename.
      #
      # @return [Array<Hash>] index
      #
      def read
        case url
        when String
          with_file_lock do
            check_file || fetch_and_save
          end
        else
          read_file || []
        end
      end

      def file
        @file ||= url ? path_to_local_file : @filename
      end

      #
      # Create path to local file
      #
      # @return [<Type>] <description>
      #
      def path_to_local_file
        File.join(Index.config.storage_dir, ".relaton", @dir, @filename)
      end

      #
      # Check if index file exists and is not older than 24 hours
      #
      # @return [Array<Hash>, nil] index or nil
      #
      def check_file
        ctime = Index.config.storage.ctime(file)
        return unless ctime && ctime > Time.now - 86400

        read_file
      end

      #
      # Check if index has correct format
      #
      # @param [Array<Hash>] index index to check
      #
      # @return [Boolean] <description>
      #
      # Structural check only. Per-id serialization is validated during
      # deserialization (see #deserialize_id), which reuses the `from_hash` the
      # index load performs anyway, so every row is checked at no extra parse
      # cost.
      def check_format(index)
        check_basic_format(index)
      end

      def check_basic_format(index)
        return false unless index.is_a? Array

        keys = %i[file id]
        index.all? { |item| item.respond_to?(:keys) && item.keys.sort == keys }
      end

      # An id is supported when `from_hash` either resolves it to a concrete
      # type (a subclass — the polymorphic `_type` matched) or round-trips
      # losslessly through `to_hash`. The subclass clause covers valid entries
      # pubid cannot fully rebuild on re-serialize (e.g. ISO directives drop a
      # redundant subgroup number); the round-trip clause covers pubid classes
      # without a subclass hierarchy. A wrong-format/garbled id satisfies
      # neither: it falls back to the bare base class and fails to round-trip.
      def id_supported?(obj, raw)
        # A concrete subtype means pubid recognized the `_type`; accept without
        # round-tripping. This both skips the false positive for valid-but-lossy
        # types (e.g. ISO directives) and avoids the costly hash compare for the
        # ~all rows that resolve to a subtype (it would otherwise add ~33%).
        return true unless obj.instance_of?(@pubid_class)

        normalize(obj.to_hash) == normalize(raw)
      rescue StandardError
        false
      end

      # Stringify hash keys and scalar values so the comparison ignores YAML
      # scalar typing (e.g. 1 vs "1") and string/symbol key differences, while
      # still detecting dropped/added keys or genuinely changed values.
      def normalize(value)
        case value
        when Hash then value.to_h { |k, v| [k.to_s, normalize(v)] }
        when Array then value.map { |v| normalize(v) }
        when nil then nil
        else value.to_s
        end
      end

      #
      # Read index from storage
      #
      # @return [Array<Hash>] index
      #
      def read_file
        yaml = Index.config.storage.read(file)
        return unless yaml

        load_index(yaml) || []
      end

      # Deserialize and sort by the same narrowing key Type#search bsearches on
      # — the base document's number, `id.root.number.to_s` (see
      # Type#candidates_by_number) — so binary search always has a consistent
      # total order. The published index is only approximately sorted (generated
      # under pubid 1.x base semantics); merely detecting sortedness left bsearch
      # disabled and every search a full O(n) scan. Sorting here is one-time per
      # load.
      def deserialize_pubid(index)
        return index unless @pubid_class

        deserialized = index.map do |r|
          { id: deserialize_id(r[:id]), file: r[:file] }
        end
        warn_unless_sorted(deserialized)
        deserialized.sort_by! { |r| r[:id].root.number.to_s }
        @sorted = true
        deserialized
      end

      # Deserialize one id and verify pubid understands it. Reuses the
      # `from_hash` deserialization the load performs anyway, so validating every
      # row costs only the `to_hash`/compare for ids that need the round-trip
      # clause. Raises InvalidIndexError when an id cannot be parsed or is
      # unsupported, so `#load_index` rejects (and re-downloads) the whole index.
      def deserialize_id(raw)
        obj = @pubid_class.from_hash(raw)
      rescue StandardError => e
        raise InvalidIndexError, "cannot parse id #{raw.inspect}: #{e.message}"
      else
        return obj if id_supported?(obj, raw)

        raise InvalidIndexError, "unsupported id #{raw.inspect}"
      end

      # Log when the loaded index is not already in narrowing-key order, so the
      # in-memory sort above (and the underlying not-sorted index file) is
      # visible. Stops at the first out-of-order pair.
      def warn_unless_sorted(index)
        prev = nil
        index.each do |r|
          num = r[:id].root.number.to_s
          if prev && prev > num
            Util.warn "Index file `#{file}` is not sorted by id number; " \
                      "sorting #{index.size} entries in memory.", progname
            return
          end
          prev = num
        end
      end

      def warn_local_index_error(reason)
        Util.info "#{reason} file `#{file}`", progname
        if url.is_a? String
          Util.info "Considering `#{file}` file corrupt, re-downloading from `#{url}`", progname
        else
          Util.info "Considering `#{file}` file corrupt, removing it.", progname
          remove
        end
      end

      def progname
        @progname ||= "relaton-#{@dir}"
      end

      def load_index(yaml, save = false)
        index = YAML.safe_load(yaml, permitted_classes: [Symbol])
        save index if save
        return deserialize_pubid(index) if check_format(index)

        report_invalid_index(save, "Wrong structure of")
      rescue Psych::SyntaxError
        report_invalid_index(save, "YAML parsing error when reading")
      rescue InvalidIndexError
        report_invalid_index(save, "Wrong structure of")
      end

      def report_invalid_index(save, reason)
        if save
          warn_remote_index_error reason
        else
          warn_local_index_error reason
        end
      end

      #
      # Fetch index from external repository and save it to storage
      #
      # @return [Array<Hash>] index
      #
      def fetch_and_save
        uri = URI.parse(url)
        body = Net::HTTP.get(uri)
        yaml = nil
        Zip::File.open_buffer(body) do |zip|
          entry = zip.entries.first
          yaml = entry.get_input_stream.read
        end
        Util.info "Downloaded index from `#{url}`", progname
        load_index(yaml, true)
      end

      def warn_remote_index_error(reason)
        Util.info "#{reason} newly downloaded file `#{file}` at `#{url}`, " \
             "the remote index seems to be invalid. Please report this " \
             "issue at https://github.com/relaton/relaton-cli.", progname
      end

      #
      # Save index to storage
      #
      # @param [Array<Hash>] index index to save
      #
      # @return [void]
      #
      def save(index)
        yaml = sort_structured_index(index).map do |item|
          item.transform_values do |value|
            @pubid_class && value.is_a?(@pubid_class) ? value.to_hash : value
          end
        end.to_yaml
        Index.config.storage.write file, yaml
        delete_sidecar
        delete_sqlite
      end

      def sort_structured_index(index)
        if @pubid_class && index.first&.dig(:id).is_a?(@pubid_class)
          index.sort_by { |item| item[:id].root.number.to_s }
        else
          index
        end
      end

      #
      # Remove index file from storage
      #
      # @return [Array]
      #
      def remove
        Index.config.storage.remove file
        delete_sidecar
        delete_sqlite
        []
      end

      #
      # Raw-row read for the lazy search path (relaton#242 stopgap): returns
      # precomputed root-number sort keys and the rows as plain hashes — no
      # pubid objects. A Marshal sidecar next to the yaml holds them so
      # repeat loads skip the YAML parse and the one-time full
      # materialization; the sidecar is rebuilt whenever the yaml is newer.
      #
      # @return [Array<Array<String>, Array<Hash>] sort keys and raw rows
      #
      def read_raw
        case url
        when String
          with_file_lock do
            check_file ? read_raw_file : fetch_raw_and_save
          end
        else
          read_raw_file || [[], []]
        end
      end

      # ── SQLite backend (relaton#242 phase 2) ──
      #
      # The downloaded index is materialized once into a SQLite database
      # keyed by the narrowing number. A search answers from a bucket query,
      # so the process holds O(bucket) rows instead of the whole index. The
      # build is pure hash transforms (no pubid objects), run in a forked
      # child so even the one-time YAML parse never lands in this process.

      def sqlite_ready?
        url.is_a?(String) && Index.config.sqlite_index != false &&
          File.file?(sqlite_db_path) && sqlite_fresh?
      end

      # Ensure the db exists and is current (24 h TTL, schema-versioned).
      def ensure_sqlite
        return false unless url.is_a?(String)
        return true if sqlite_ready?

        with_file_lock do
          build_sqlite unless sqlite_ready?
        end
        sqlite_ready?
      end

      def sqlite_bucket(number)
        sqlite_backend.bucket(number)
      end

      def sqlite_count
        sqlite_backend.count
      end

      def close_sqlite
        @sqlite_backend&.close
        @sqlite_backend = nil
      end

      def delete_sqlite
        close_sqlite
        File.delete(sqlite_db_path) if File.file?(sqlite_db_path)
      rescue Errno::EACCES
        nil
      end

      def sqlite_db_path
        "#{path_to_local_file}.db"
      end

      private

      def sqlite_backend
        @sqlite_backend ||= SqliteBackend.new(sqlite_db_path, pubid_class: @pubid_class)
      end

      def sqlite_fresh?
        ctime = Index.config.storage.ctime(sqlite_db_path)
        backend = sqlite_backend
        ctime && ctime > Time.now - 86400 && !backend.stale_schema?
      rescue SQLite3::SQLException
        false
      ensure
        backend&.close
        @sqlite_backend = nil
      end

      # The build downloads the published zip, converts its rows to
      # `[number, sort_key, id_json, file]` tuples by hash transforms alone,
      # and writes the db — in a forked child where the YAML parse's memory
      # dies with the process.
      def build_sqlite
        # The whole build — download, YAML parse, db write — runs in a
        # forked child where available: the parse's ~300 MB (per flavor,
        # larger for IETF) dies with the child, and the serving process
        # never allocates it.
        if Process.respond_to?(:fork) && !ENV["RELATON_NO_FORK"]
          pid = Process.fork do
            tuples = download_tuples
            write_sqlite(tuples) if tuples
            exit!(0)
          end
          Process.wait(pid)
          true
        else
          tuples = download_tuples
          return false unless tuples

          write_sqlite(tuples)
        end
      end

      def write_sqlite(tuples)
        File.dirname(sqlite_db_path).then { |d| require "fileutils"; FileUtils.mkdir_p(d) }
        backend = SqliteBackend.new(sqlite_db_path, pubid_class: @pubid_class)
        backend.build(tuples.each)
        backend.close
      end

      # Enumerate `[number, sort_key, id_hash, file]` from the published zip.
      # The root number — the base document's, walking `base` nesting — is
      # computed on the raw hash; no pubid object is ever built.
      def download_tuples
        body = Net::HTTP.get(URI.parse(url))
        # rubyzip may mutate the buffer it is handed; a StringIO over a copy
        # keeps the response body intact for any later reader of it.
        yaml = nil
        Zip::File.open_buffer(StringIO.new(body.dup)) do |zip|
          stream = zip.entries.first.get_input_stream
          yaml = stream.read
        end
        yaml = yaml.read unless yaml.is_a?(String)
        Util.info "Downloaded index from `#{url}` for sqlite materialization", progname
        raw = YAML.safe_load(yaml, permitted_classes: [Symbol])
        return nil unless check_format(raw)

        Enumerator.new do |y|
          raw.each do |r|
            number = raw_root_number(r[:id]).to_s
            y << [number, number, r[:id], r[:file]]
          end
        end
      rescue Psych::SyntaxError, SocketError, OpenURI::HTTPError, Errno::ECONNRESET,
             OpenSSL::SSL::SSLError => e
        Util.info "SQLite index build failed (#{e.message}); falling back", progname
        nil
      end

      # `#root` as a hash walk: a supplement nests its origin under `base`,
      # and the flattened to_hash puts the supplement's own components first.
      # Accepts string and symbol keys — a YAML round-trip with permitted
      # Symbol may give either.
      def raw_root_number(id_hash)
        return nil unless id_hash.is_a?(Hash)

        base = id_hash["base"] || id_hash[:base]
        return raw_root_number(base) if base

        id_hash["number"] || id_hash[:number]
      end

      public

      # Deserialize raw rows into pubid rows. Only the caller knows which
      # slice it needs, so materialization happens here rather than at load.
      #
      # @param [Array<Hash>] rows raw rows
      # @return [Array<Hash>] rows with deserialized ids
      def materialize(rows)
        return rows unless @pubid_class

        rows.map { |r| { id: deserialize_id(r[:id]), file: r[:file] } }
      end

      # Save raw rows (possibly alongside the keys they were loaded with);
      # sorts by the same root-number key the object path sorts by.
      #
      # @param [Array<String>] keys sort keys, parallel to rows
      # @param [Array<Hash>] rows raw rows
      # @return [void]
      def save_raw(keys, rows)
        ordered = @pubid_class ? keys.zip(rows).sort_by { |k, _| k.to_s }
                                     .map { |_, r| r } : rows
        yaml = ordered.map do |item|
          { id: item[:id], file: item[:file] }
        end.to_yaml
        Index.config.storage.write file, yaml
        delete_sidecar
      end

      private

      def sidecar_file
        "#{file}.ms"
      end

      def delete_sidecar
        File.delete(sidecar_file) if File.file?(sidecar_file)
      rescue Errno::EACCES
        nil
      end

      def read_raw_file
        # The sidecar is authoritative while it describes the yaml byte-for-byte
        # (same size) — the yaml is not even parsed until the sidecar is stale
        # or unreadable.
        if sidecar_fresh?
          loaded = sidecar
          return loaded if loaded
        end

        yaml = Index.config.storage.read(file)
        return unless yaml

        begin
          raw = YAML.safe_load(yaml, permitted_classes: [Symbol])
        rescue Psych::SyntaxError
          warn_local_index_error("YAML parsing error when reading")
          delete_sidecar
          return [[], []]
        end
        build_raw(raw)
      end

      # Size, not mtime: NTFS timestamp coarseness makes a rewritten yaml
      # carry the sidecar's own mtime, so "yaml is newer" misses the rebuild.
      def sidecar_fresh?
        File.file?(sidecar_file) && File.file?(file) &&
          File.size(file) == sidecar_yaml_size
      end

      def sidecar_yaml_size
        Marshal.load(File.binread(sidecar_file))[4]
      rescue TypeError, ArgumentError, EOFError
        nil
      end

      def sidecar
        version, sorted, keys, rows = Marshal.load(File.binread(sidecar_file))
        return unless version == SIDECAR_VERSION

        @sorted = sorted
        [keys, rows]
      rescue TypeError, ArgumentError, EOFError
        nil
      end

      def build_raw(raw)
        unless check_format(raw)
          warn_local_index_error("Wrong structure of")
          return [[], []]
        end

        return build_raw_in_child(raw) if build_sidecar_in_child?

        build_raw_in_process(raw)
      rescue InvalidIndexError
        warn_local_index_error("Wrong structure of")
        [[], []]
      end

      # The one-time key build materializes every row (~675 MB on the
      # 79,993-row ISO index). Freed pages are often not returned to the OS,
      # so an in-process build leaves the parent's RSS high — and containers
      # OOM on RSS (relaton#242). Where fork exists, build the sidecar in a
      # child: the graph dies with it and the parent never spikes.
      def build_sidecar_in_child?
        Process.respond_to?(:fork) && Index.config.build_sidecar_in_child != false
      end

      def build_raw_in_child(raw)
        pid = Process.fork do
          build_raw_in_process(raw)
          exit!(0)
        end
        Process.wait(pid)
        loaded = sidecar
        return build_raw_in_process(raw) unless loaded # child failed

        loaded
      rescue Errno::ENOMEM, SystemCallError
        build_raw_in_process(raw)
      end

      def build_raw_in_process(raw)
        objects = deserialize_pubid(raw)
        keys = objects.map { |r| r[:id].root.number.to_s }
        rows = objects.map { |r| { id: raw_id(r), file: r[:file] } }
        write_sidecar(keys, rows)
        [keys, rows]
      rescue InvalidIndexError
        warn_local_index_error("Wrong structure of")
        [[], []]
      end

      def raw_id(row)
        id = row[:id]
        id.respond_to?(:to_hash) ? id.to_hash : id
      end

      def write_sidecar(keys, rows)
        File.binwrite(sidecar_file,
                      Marshal.dump([SIDECAR_VERSION, @sorted, keys, rows,
                                    File.size(file)]))
      rescue Errno::EACCES, Errno::ENOENT, Errno::EROFS
        nil # the sidecar is an optimization; a read-only dir still works
      end

      def fetch_raw_and_save
        uri = URI.parse(url)
        body = Net::HTTP.get(uri)
        yaml = nil
        Zip::File.open_buffer(body) do |zip|
          yaml = zip.entries.first.get_input_stream.read
        end
        Util.info "Downloaded index from `#{url}`", progname
        raw = YAML.safe_load(yaml, permitted_classes: [Symbol])
        if check_format(raw)
          save raw
          raw = nil # release the parsed copy; read_raw_file loads the sidecar's
          read_raw_file
        else
          warn_remote_index_error "Wrong structure of"
          [[], []]
        end
      rescue Psych::SyntaxError
        warn_remote_index_error "YAML parsing error when reading"
        [[], []]
      end

      def with_file_lock(&)
        @@file_locks_mutex.synchronize do
          @@file_locks[file] ||= Mutex.new
        end

        @@file_locks[file].synchronize(&)
      end
    end
  end
end
