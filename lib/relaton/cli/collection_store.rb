require "fileutils"
require "time"
require "yaml"
require "lutaml/store"
require_relative "../bibcollection"
require_relative "util"

module Relaton
  module Cli
    # The collections of `relaton collection` (relaton#549): one lutaml-store
    # FileSystem store under `<dir>/v2/`, keyed by the collection name the
    # user types. Each value is the collection's YAML (`{"root" => …}`, as
    # `Bibcollection#to_h` makes it) with a top-level `updated` time, so the
    # data file is the same YAML an older relaton wrote.
    #
    # lutaml-store is the only storage layer, as for `Db::Cache` (relaton#548):
    # its lock makes a read-modify-write atomic between threads and processes,
    # and its rename makes a write atomic. Nothing here builds a path from a
    # name or takes a lock of its own. The one raw IO is the one-time move of
    # the flat files an older relaton wrote directly in `<dir>`: each is
    # imported, then moved to `<dir>-v1.bak/`, never deleted.
    class CollectionStore
      LAYOUT = "v2".freeze
      UPDATED = "updated".freeze

      attr_reader :dir

      # @param dir [String] the collections directory
      def initialize(dir)
        @dir = dir
        @store = Lutaml::Store::BasicStore.new(
          adapter_type: :filesystem,
          adapter_options: { path: File.join(dir, LAYOUT), extension: ".yaml",
                             integrity_checks: false,
                             create_directories: false },
          cache: { enabled: false },
        )
        move_flat_files
      end

      # @param pattern [String] a glob over the names (`--collection`)
      # @return [Array<String>] the matching names, sorted
      def names(pattern = "*")
        @store.keys.select { |name| File.fnmatch pattern, name }.sort
      end

      # @param name [String]
      def exist?(name)
        @store.exists? name
      end

      # @param name [String]
      # @return [Relaton::Bibcollection, nil]
      def get(name)
        hash = read name
        Relaton::Bibcollection.new hash["root"] if hash
      end

      # @param name [String]
      # @return [Time, nil] when the collection was last written
      def updated(name)
        time = read(name)&.dig UPDATED
        Time.iso8601 time if time
      end

      # @param name [String]
      # @return [Integer, nil] the size of the stored collection, in bytes
      def size(name)
        @store.get(name)&.bytesize
      end

      # @param name [String]
      # @param coll [Relaton::Bibcollection]
      # @return [Boolean] false when the store already holds the name
      def create(name, coll)
        @store.adapter.transaction do
          next false if @store.exists? name

          @store.set name, encode(coll.to_h)
          true
        end
      end

      # Atomic read-modify-write under the store's exclusive lock.
      #
      # @param name [String]
      # @yieldparam coll [Relaton::Bibcollection, nil] nil when it is missing
      # @yieldreturn [Relaton::Bibcollection]
      def update(name)
        @store.update(name) do |value|
          hash = decode value if value
          coll = hash && Relaton::Bibcollection.new(hash["root"])
          encode yield(coll).to_h
        end
      end

      private

      # @return [Hash, nil]
      def read(name)
        value = @store.get name
        decode value if value
      end

      def decode(value)
        YAML.safe_load value, permitted_classes: [Date, Time, Symbol],
                              aliases: true
      end

      def encode(hash, updated = Time.now)
        hash.merge(UPDATED => updated.utc.iso8601).to_yaml
      end

      # A flat collection file is imported unless the store already holds its
      # name, and then moved to the backup either way, under the store's lock
      # so two processes do not move one file. The scan runs again inside the
      # lock: another process can have moved the files first.
      def move_flat_files
        return if flat_collections.empty?

        @store.adapter.transaction do
          flat_collections(warn: false).each do |name, path, hash|
            if @store.exists? name
              Util.warn "collections #{dir}: `#{name}` is in the store; " \
                        "the flat file is not imported, moved to #{backup path}"
            else
              @store.set name, encode(hash, File.mtime(path))
              Util.info "collections #{dir}: `#{name}` imported, the flat " \
                        "file moved to #{backup path}"
            end
          end
        end
      end

      # @param warn [Boolean] warn about a file that is not valid YAML
      # @return [Array<Array(String, String, Hash)>] name, path and YAML of
      #   each file directly in the directory that holds a collection
      def flat_collections(warn: true)
        return [] unless Dir.exist? dir

        Dir.children(dir).sort.filter_map do |name|
          path = File.join dir, name
          next unless File.file?(path) && !name.start_with?(".")

          hash = YAML.safe_load File.read(path, encoding: "UTF-8"),
                                permitted_classes: [Date, Time, Symbol],
                                aliases: true
          [name, path, hash] if hash.is_a?(Hash) && hash["root"].is_a?(Hash)
        rescue Psych::Exception, ArgumentError => e
          Util.warn "the file `#{path}` isn't a collection: #{e.message}" if warn
          nil
        rescue Errno::ENOENT
          nil # another process moved it
        end
      end

      # Moves a file to `<dir>-v1.bak/`; a name the backup already holds
      # takes a numeric suffix.
      # @return [String] the backup path
      def backup(path)
        bak = "#{File.expand_path dir}-v1.bak" # `dir/` must not put it inside
        FileUtils.mkdir_p bak
        target = File.join bak, File.basename(path)
        n = 0
        target = File.join(bak, "#{File.basename path}.#{n += 1}") while File.exist? target
        FileUtils.mv path, target
        target
      end
    end
  end
end
