# frozen_string_literal: true

module Relaton
  module Index
    # A document's family: every index row whose root number matches the
    # reference's — the base document, its editions, parts, and any supplement
    # layer (root walks a wrapper's base chain). Rows are the same
    # `{ id:, file: }` hashes #search returns.
    #
    # The views are driven by the components the identifiers actually state:
    # #editions groups rows by year/edition/version, #parts by part/parts.
    # An identifier that states none of those appears only in #members.
    class Family
      attr_reader :reference, :members

      def initialize(reference, members)
        @reference = reference
        @members = members
      end

      # @return [String] the family's narrowing key
      def root_number
        reference.root.number.to_s
      end

      # Rows grouped by their stated edition, ascending.
      # @return [Hash{String => Array<Hash>}]
      def editions
        group_by(%w[year edition version])
      end

      # Rows grouped by their stated part, ascending.
      # @return [Hash{String => Array<Hash>}]
      def parts
        group_by(%w[part parts subpart])
      end

      private

      def group_by(names)
        grouped = Hash.new { |hash, key| hash[key] = [] }
        members.each do |row|
          value = component(row[:id], names)
          grouped[value] << row unless value.empty?
        end
        grouped.sort_by { |key, _| key }.to_h
      end

      def component(id, names)
        hash = id.root.to_hash
        names.each do |name|
          value = hash[name]
          next if value.nil?

          value = value.first if value.is_a?(Array)
          text = value.to_s
          return text unless text.strip.empty?
        end
        ""
      end
    end
  end
end
