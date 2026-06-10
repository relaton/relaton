module Relaton
  module Index
    #
    # File IO class is used to read and write index files.
    # In searh mode url is used to fetch index from external repository and save it to storage.
    # In index mode url should be nil.
    #
    class FileIO
      include IdNumber

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
      def initialize(dir, url, filename, id_keys, pubid_class = nil)
        @dir = dir
        @url = url
        @filename = filename
        @id_keys = id_keys || []
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
      def check_format(index)
        check_basic_format(index) && check_id_format(index)
      end

      def check_basic_format(index)
        return false unless index.is_a? Array

        keys = %i[file id]
        index.all? { |item| item.respond_to?(:keys) && item.keys.sort == keys }
      end

      def check_id_format(index)
        return true if @id_keys.empty?

        keys = index.each_with_object(Set.new) do |item, acc|
          acc.merge item[:id].keys if item[:id].is_a?(Hash)
        end
        keys.none? { |k| !@id_keys.include? k }
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
          { id: @pubid_class.from_hash(r[:id]), file: r[:file] }
        end
        warn_unless_sorted(deserialized)
        deserialized.sort_by! { |r| get_id_number(r[:id]) }
        @sorted = true
        deserialized
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
        return deserialize_pubid(index) if check_format index

        if save
          warn_remote_index_error "Wrong structure of"
        else
          warn_local_index_error "Wrong structure of"
        end
      rescue Psych::SyntaxError
        if save
          warn_remote_index_error "YAML parsing error when reading"
        else
          warn_local_index_error "YAML parsing error when reading"
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
