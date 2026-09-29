require "fileutils"
require "digest"
require "json"
require "date"
require "lutaml/store"
require_relative "cache_entry"

module Relaton
  class Db
    #
    # The document cache of one directory, on two lutaml-store FileSystem
    # stores under `<dir>/v2/`:
    #
    # - `rows/` holds the index. One store key per bucket, `<flavor>/<root
    #   number>` (e.g. `iso/19115`), whose value is the list of the bucket's
    #   CacheEntry rows. A lookup reads one small bucket, and a write is one
    #   atomic `update` of it.
    # - `docs/` holds the XML documents. A document is named after the row it
    #   was stored for, and several rows can point to it.
    #
    # A key is a parsed pubid, a wrapped string (`ISO(ISO 19115-1)`, parsed
    # through the prefix's processor), or a plain string that no processor
    # owns. Locking and atomic writes come from lutaml-store.
    #
    class Cache
      LAYOUT = "v2".freeze
      VERSIONS_KEY = "_versions".freeze
      STRING_FLAVOR = "_key".freeze
      PUBID_FLAVOR = "_pubid".freeze
      NOT_FOUND = /\Anot_found/
      UNDATED_TTL = 60
      WRAPPED_KEY = /\A(?<prefix>[^(\s]+)\((?<code>.+)\)\z/m
      # What a row may add to a dated key and still answer it: `===` also
      # reads an omitted `part` as "any part" (`ISO 19115:2003 ===
      # ISO 19115-1:2003`), which names another document.
      LANGUAGE_COMPONENTS = %w[language languages].freeze
      # What a row may add to a key and still be one of its editions.
      EDITION_COMPONENTS = (%w[year date month] + LANGUAGE_COMPONENTS).freeze

      # @return [String]
      attr_reader :dir

      # @param dir [String] cache directory
      def initialize(dir)
        @dir = dir
        # A stale file at the cache path (e.g. a placeholder left by cache
        # migration flows) makes every write raise Errno::EEXIST; replace
        # it with the cache directory.
        FileUtils.rm_rf dir if File.exist?(dir) && !File.directory?(dir)
        archive_old_layout
        open_stores
        check_versions
      end

      # Move the cache to another directory.
      # @param new_dir [String, nil]
      # @return [String, nil] the new directory
      def mv(new_dir)
        return unless new_dir

        if File.exist? new_dir
          Util.info "target directory exists `#{new_dir}`"
          return
        end

        FileUtils.mv dir, new_dir
        @dir = new_dir
        open_stores
        @dir
      end

      # Remove every row and document.
      def clear
        @rows.clear
        @docs.clear
        @versions = {}
      end

      # Read the document (or `not_found <date>`) for a key: the row with
      # this key, else, for a dated pubid, a row the key is a subset of.
      #
      # @param key [Pubid::Identifier, String]
      # @return [String, nil]
      def [](key)
        found = lookup(key)
        found && read_entry(found.last)
      end
      alias get []

      # @param key [Pubid::Identifier, String]
      # @param value [String, nil] document XML or `not_found <date>`; nil
      #   deletes the row
      def []=(key, value)
        store key, value
      end

      #
      # Save a document for a query key. When the document's own identifier
      # (`item_key`) differs from the query, both get a row, and both rows
      # point to one document file.
      #
      # @param key [Pubid::Identifier, String] query key
      # @param value [String, nil] document XML or `not_found <date>`
      # @param item_key [Pubid::Identifier, String, nil] the document's key
      # @return [String, nil] value
      #
      def store(key, value, item_key: nil) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        return delete(key) if value.nil?

        bucket, key = resolve key
        fetched = fetched_of value
        record_version bucket
        if value.match? NOT_FOUND
          upsert bucket, entry(key, CacheEntry::NOT_FOUND, nil, fetched)
          return value
        end

        item_bucket, item_key = item_key ? resolve(item_key) : [bucket, key]
        file = doc_name item_bucket, item_key
        record_version item_bucket
        @rows.adapter.transaction do
          @docs.set file, value
          upsert item_bucket, entry(item_key, CacheEntry::DOC, file, fetched)
          unless canonical(key) == canonical(item_key)
            upsert bucket, entry(key, CacheEntry::DOC, file, fetched)
          end
        end
        value
      end

      # Delete the row of a key. Its document goes too, when no other row
      # points to it.
      # @param key [Pubid::Identifier, String]
      def delete(key)
        bucket, key = resolve key
        target = canonical key
        return unless read_bucket(bucket).any? { |row| row_key(row) == target }

        delete_row bucket, target
      end

      #
      # Delete the row a lookup of the key finds (its own, or the one a dated
      # key is a subset of) when it is no longer valid.
      #
      # @param key [Pubid::Identifier, String]
      # @param year [String, nil]
      #
      def expire(key, year)
        found = lookup(key) or return
        return if valid_row?(found.last, year)

        delete_row resolve(found.first).first, row_key(found.last)
      end

      #
      # Save the row of a key, and its document, from another cache.
      #
      # @param key [Pubid::Identifier, String]
      # @param other [Relaton::Db::Cache]
      #
      def clone_entry(key, other)
        found = other.lookup(key) or return
        row_id, row = found
        store row_id, other.read_entry(row)
      end

      # @param key [Pubid::Identifier, String]
      # @return [String, nil] the date the entry was fetched
      def fetched(key)
        lookup(key)&.last&.dig("fetched")
      end

      # An undated entry expires after 60 days, a dated one never.
      # @param key [Pubid::Identifier, String]
      # @param year [String, nil]
      def valid_entry?(key, year)
        found = lookup(key)
        found ? valid_row?(found.last, year) : false
      end

      #
      # The cached editions of the key: documents whose pubid the key is a
      # subset of (`key === id`) and that add only a year, a date or a
      # language to it. For a query that selects among editions (e.g. by
      # publication date).
      #
      # @param key [Pubid::Identifier]
      # @return [Array<Array(Pubid::Identifier, String)>]
      #
      def candidates(key) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
        bucket, key = resolve key
        return [] if key.is_a? String

        read_bucket(bucket).filter_map do |row|
          next if row["status"] != CacheEntry::DOC || !row["id"]

          id = pubid_from row["id"]
          next unless subset_of? key, id, row["id"], EDITION_COMPONENTS

          xml = @docs.get row["file"]
          [id, xml] if xml
        end
      end

      #
      # Every cached document once.
      #
      # @yieldparam processor [Relaton::Core::Processor, nil] the owning flavor
      # @yieldparam xml [String]
      # @return [Array] the documents, or the block results
      #
      def all
        files = {}
        each_row do |bucket, row|
          files[row["file"]] ||= bucket if row["file"]
        end
        files.filter_map do |file, bucket|
          xml = @docs.get(file) or next
          block_given? ? yield(processor_for(bucket), xml) : xml
        end
      end

      # @return [Array<Hash>] every row
      def rows
        list = []
        each_row { |_, row| list << row }
        list
      end

      # The row of a key, with the key it is stored under.
      # @param key [Pubid::Identifier, String]
      # @return [Array(Object, Hash), nil]
      def lookup(key)
        bucket, key = resolve key
        rows = read_bucket bucket
        target = canonical key
        row = rows.detect { |r| row_key(r) == target }
        return [key, row] if row
        return unless dated? key

        subset_match rows, key
      end

      # @param row [Hash]
      # @return [String, nil] document XML or `not_found <date>`
      def read_entry(row)
        return "not_found #{row['fetched']}" if row["status"] == CacheEntry::NOT_FOUND

        @docs.get row["file"]
      end

      private

      def open_stores
        base = File.join dir, LAYOUT
        @rows = new_store File.join(base, "rows"), ".json"
        @docs = new_store File.join(base, "docs"), ".xml"
      end

      def new_store(path, extension)
        Lutaml::Store::BasicStore.new(
          adapter_type: :filesystem,
          adapter_options: { path: path, extension: extension,
                             integrity_checks: false },
          cache: { enabled: false },
        )
      end

      # A cache written by the file-per-key layout (before v2) is moved to
      # `<dir>-v1.bak`, never deleted.
      def archive_old_layout # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        return unless Dir.exist? dir

        old = Dir.children(dir) - [LAYOUT]
        bak = "#{dir}-v1.bak"
        # Once only: an older relaton that shares the directory writes the old
        # layout again, and v2 ignores it.
        return if old.empty? || File.exist?(bak)

        FileUtils.mkdir_p bak
        old.each do |name|
          FileUtils.mv File.join(dir, name), bak
        rescue Errno::ENOENT
          next # another process moved it first
        end
        Util.info "cache #{dir}: the old cache is moved to #{bak}"
      end

      # Drop the rows and documents of a flavor whose grammar changed since
      # they were written.
      def check_versions
        @versions = @rows.get(VERSIONS_KEY) || {}
        @versions.each do |flavor, hash|
          processor = Registry.instance[:"relaton_#{flavor}"]
          next if processor && processor.grammar_hash == hash

          drop_flavor flavor
          Util.info "cache #{dir}: version of `#{flavor}` is obsolete " \
                    "and its entries are cleared."
        end
      end

      def drop_flavor(flavor)
        @rows.adapter.transaction do
          [@rows, @docs].each do |store|
            store.each_key { |k| store.delete k if k.start_with? "#{flavor}/" }
          end
          @versions = @rows.update(VERSIONS_KEY) { |v| (v || {}).except flavor }
        end
      end

      def record_version(bucket)
        flavor = bucket.split("/", 2).first
        return if flavor.start_with?("_") || @versions.key?(flavor)

        processor = Registry.instance[:"relaton_#{flavor}"] or return
        hash = processor.grammar_hash
        @versions = @rows.update(VERSIONS_KEY) do |v|
          (v || {}).merge(flavor => hash)
        end
      end

      # @return [Array(String, Object)] the bucket and the resolved key
      def resolve(key)
        key = wrapped_key key if key.is_a? String
        if key.is_a? String
          ["#{STRING_FLAVOR}/#{key}", key]
        else
          [bucket_for(key), key]
        end
      end

      # `ISO(ISO 19115-1)` -> the ISO processor's pubid for `ISO 19115-1`.
      def wrapped_key(key)
        match = key.match(WRAPPED_KEY) or return key
        processor = Registry.instance.by_type(match[:prefix]) or return key
        processor.cache_key(match[:code], nil, {}) || key
      end

      def bucket_for(pubid)
        processor = Registry.instance.processor_by_pubid pubid
        flavor = processor ? flavor_name(processor) : PUBID_FLAVOR
        number = pubid.root.number.to_s
        # No number (DOI, ISBN, the SI Brochure): 256 digest buckets, not one
        # bucket for the whole flavor.
        number = "~#{digest(pubid)[0, 2]}" if number.empty?
        "#{flavor}/#{number}"
      end

      def flavor_name(processor)
        processor.short.to_s.delete_prefix "relaton_"
      end

      def processor_for(bucket)
        flavor = bucket.split("/", 2).first
        if flavor == STRING_FLAVOR
          Registry.instance.processor_by_ref bucket.split("/", 2).last
        else
          Registry.instance[:"relaton_#{flavor}"]
        end
      end

      def read_bucket(bucket)
        Array @rows.get(bucket)
      end

      def each_row
        @rows.each_key do |bucket|
          next if bucket == VERSIONS_KEY

          read_bucket(bucket).each { |row| yield bucket, row }
        end
      end

      # Replace or add a row. A document the replaced row pointed to goes
      # when no row points to it any more.
      def upsert(bucket, row) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        target = row_key row
        replaced = nil
        @rows.adapter.transaction do
          @rows.update(bucket) do |old|
            old = Array(old)
            replaced = old.detect { |r| row_key(r) == target }
            (old - [replaced]) << row
          end
          old_file = replaced&.dig("file")
          remove_doc old_file, bucket if old_file && old_file != row["file"]
        end
      end

      def delete_row(bucket, target)
        @rows.adapter.transaction do
          removed = nil
          rows = @rows.update(bucket) do |old|
            old = Array(old)
            removed = old.detect { |row| row_key(row) == target }
            old - [removed]
          end
          @rows.delete bucket if rows.empty?
          remove_doc removed["file"], bucket if removed&.dig("file")
        end
      end

      def valid_row?(row, year)
        return false unless read_entry(row)

        year || Date.today - Date.parse(row["fetched"]) < UNDATED_TTL
      end

      #
      # Whether a row answers a key: the key is a subset of it (`===`), and
      # every component the row adds is one of `allowed`.
      #
      # @param key [Pubid::Identifier]
      # @param id [Pubid::Identifier] the row's pubid
      # @param row_id [Hash] the row's stored `id`
      # @param allowed [Array<String>]
      #
      def subset_of?(key, id, row_id, allowed)
        return false unless key === id # rubocop:disable Style/CaseEquality

        (added_components(canonical(key), row_id) - allowed).empty?
      end

      # The names of the components `row` has and `query` has not, at any
      # depth (a supplement's base, an adoption's adopted document).
      def added_components(query, row) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
        case row
        when Hash
          row.flat_map do |name, value|
            next [] if value.nil?
            next [name] unless query.is_a?(Hash) && query.key?(name)

            added_components query[name], value
          end
        when Array
          return ["[]"] unless query.is_a?(Array) && query.size == row.size

          row.each_with_index.flat_map { |v, i| added_components query[i], v }
        else []
        end
      end

      def entry(key, status, file, fetched)
        row = CacheEntry.new(status: status, file: file, fetched: fetched)
        if key.is_a?(String) then row.key = key
        else row.id = canonical(key)
        end
        row.to_hash
      end

      # A key as it is stored: a pubid's `to_hash` after a JSON round trip,
      # so a fresh key compares equal to a stored one.
      def canonical(key)
        return key if key.is_a? String

        JSON.parse JSON.generate(key.to_hash)
      end

      def row_key(row)
        row["id"] || row["key"]
      end

      def dated?(key)
        !key.is_a?(String) && key.respond_to?(:year) && !key.year.nil?
      end

      # The newest row whose pubid the key is a subset of. A row whose
      # document is gone does not count.
      def subset_match(rows, key) # rubocop:disable Metrics/CyclomaticComplexity
        rows.filter_map do |row|
          next unless row["id"]

          id = pubid_from row["id"]
          next unless subset_of? key, id, row["id"], LANGUAGE_COMPONENTS
          next if row["file"] && !@docs.exists?(row["file"])

          [id, row]
        end.max_by { |_, row| row["fetched"].to_s }
      end

      def pubid_from(hash)
        require "pubid"
        ::Pubid.from_hash hash
      end

      def doc_name(bucket, key)
        "#{bucket}/#{digest(key)[0, 16]}"
      end

      # A digest of the canonical key, independent of the hash order.
      def digest(key)
        Digest::SHA256.hexdigest JSON.generate(canonical_sorted(key))
      end

      def canonical_sorted(key)
        value = canonical key
        value.is_a?(Hash) ? deep_sort(value) : value
      end

      def deep_sort(value)
        case value
        when Hash then value.sort.to_h { |k, v| [k, deep_sort(v)] }
        when Array then value.map { |v| deep_sort v }
        else value
        end
      end

      # Delete a document unless a row still points to it. A row that points
      # to it lives in the deleted row's bucket or in the document's own one.
      def remove_doc(file, bucket)
        file_bucket = file.rpartition("/").first
        used = [bucket, file_bucket].uniq.any? do |b|
          read_bucket(b).any? { |row| row["file"] == file }
        end
        @docs.delete file unless used
      end

      def fetched_of(value)
        date = if value.match? NOT_FOUND then value[/\d{4}-\d{2}-\d{2}/]
               else value[%r{<fetched>\s*([^<\s]+)\s*</fetched>}, 1]
               end
        date || Date.today.to_s
      end
    end
  end
end
