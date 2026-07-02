module Relaton
  module Index
    #
    # File IO class is used to read and write index files.
    # In searh mode url is used to fetch index from external repository and save it to storage.
    # In index mode url should be nil.
    #
    class FileIO
      include IdNumber

      # Raised internally when a deserialized id cannot be parsed or is not
      # understood by the pubid class; `#load_index` rescues it to trigger the
      # wrong-structure handling (re-download, or stop and log).
      class InvalidIndexError < StandardError; end

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
      # `id_keys` is accepted for backward compatibility but no longer used: the
      # index format is now validated by round-tripping a sample of ids through
      # the pubid class (see #check_serialization), which understands the pubid
      # v2 (lutaml) `_type` serialization that the old key-allowlist could not.
      def initialize(dir, url, filename, _id_keys = nil, pubid_class = nil)
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

      # Deserialize and sort by the same narrowing key Type#search bsearches
      # on, so binary search always has a consistent total order. The published
      # index is only approximately sorted (generated under pubid 1.x base
      # semantics); merely detecting sortedness left bsearch disabled and every
      # search a full O(n) scan. Sorting here is one-time per load.
      def deserialize_pubid(index)
        return index unless @pubid_class

        deserialized = index.map do |r|
          { id: deserialize_id(r[:id]), file: r[:file] }
        end
        warn_unless_sorted(deserialized)
        deserialized.sort_by! { |r| get_id_number(r[:id]) }
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

      # Log when the loaded index is not already in get_id_number order, so the
      # in-memory sort above (and the underlying not-sorted index file) is
      # visible. Stops at the first out-of-order pair.
      def warn_unless_sorted(index)
        prev = nil
        index.each do |r|
          num = get_id_number(r[:id])
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
      end

      def sort_structured_index(index)
        if @pubid_class && index.first&.dig(:id).is_a?(@pubid_class)
          index.sort_by { |item| get_id_number item[:id] }
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
        []
      end

      private

      def with_file_lock(&)
        @@file_locks_mutex.synchronize do
          @@file_locks[file] ||= Mutex.new
        end

        @@file_locks[file].synchronize(&)
      end
    end
  end
end
