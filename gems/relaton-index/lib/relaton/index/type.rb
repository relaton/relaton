module Relaton
  module Index
    #
    # Relaton::Index::Type is a class for indexing Relaton files.
    #
    class Type
      #
      # Initialize a new Relaton::Index::Type object
      #
      # @param [String, Symbol] type type of index (ISO, IEC, etc.)
      # @param [String, nil] url external URL to index, used to fetch index for searching files
      # @param [String, nil] file output file name
      # @param [Array<Symbol>] id_keys keys of identifier to be used for sorting index
      #   format of index file is checked if id_keys all is provided at least in one of the IDs
      # @param [Pubid::Core::Identifier::Base, nil] pubid class for deserialization
      #
      def initialize(type, url = nil, file = nil, id_keys = nil, pubid_class = nil) # rubocop:disable Metrics/ParameterLists
        @file = file
        filename = file || Index.config.filename
        @file_io = FileIO.new type.to_s.downcase, url, filename, id_keys, pubid_class
      end

      def index
        @index ||= @file_io.read
      end

      #
      # Check if index is actual. If url or file is given, check if it is equal to
      # index url or file.
      #
      # @param [Hash] **args arguments
      # @option args [String, nil] :url external URL to index, used to fetch index for searching files
      # @option args [String, nil] :file output file name
      #
      # @return [Boolean] true if index is actual, false otherwise
      #
      def actual?(**args)
        (!args.key?(:url) || args[:url] == @file_io.url) && (!args.key?(:file) || args[:file] == @file)
      end

      #
      # Add or update index item
      #
      # @param [Pubid::Core::Identifier::Base] id document ID
      # @param [String] file file name of the document
      #
      # @return [void]
      #
      def add_or_update(id, file)
        key = id.to_s
        item = id_lookup[key]
        if item
          item[:file] = file
        else
          new_item = { id: id, file: file }
          index << new_item
          id_lookup[key] = new_item
          @file_io.sorted = false
        end
      end

      #
      # Search index for a given ID
      #
      # @param [String, Pubid::Core::Identifier::Base] id ID to search for
      #
      # @return [Array<Hash>] search results
      #
      def search(id = nil, &block)
        items = search_candidates(id)
        return items.select(&block) if block

        items.select { |i| match_item(i, id) }
      end

      #
      # Save index to storage
      #
      # @return [void]
      #
      def save
        @file_io.save(@index || [])
      end

      #
      # Remove index file from storage and clear index
      #
      # @return [void]
      #
      def remove_file
        @file_io.remove
        @index = nil
        @id_lookup = nil
      end

      #
      # Remove all index items
      #
      # @return [void]
      #
      def remove_all
        @index = []
        @id_lookup = nil
        @file_io.sorted = true
      end

      private

      def id_lookup
        @id_lookup ||= index.each_with_object({}) do |item, h|
          h[item[:id].to_s] = item
        end
      end

      def search_candidates(id)
        # index needs to be created to check if sorted
        idx = index
        if @file_io.sorted && id && !id.is_a?(String)
          candidates_by_number(id)
        else
          idx
        end
      end

      def candidates_by_number(id)
        target = get_id_number(id)
        left = bsearch_left(target)
        return [] unless left

        right = bsearch_right(target)
        index[left...right]
      end

      def get_id_number(id)
        id.respond_to?(:base) && id.base ? id.base.number.to_s : id.number.to_s
      end

      def bsearch_left(target)
        index.bsearch_index do |item|
          get_id_number(item[:id]) >= target
        end
      end

      def bsearch_right(target)
        index.bsearch_index do |item|
          get_id_number(item[:id]) > target
        end || index.size
      end

      def match_item(item, id)
        if item[:id].is_a?(String)
          item[:id].include?(id.is_a?(String) ? id : id.to_s)
        elsif id.is_a?(String)
          item[:id].to_s.include?(id)
        else
          item[:id] == id
        end
      end
    end
  end
end
