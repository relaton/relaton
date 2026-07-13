# frozen_string_literal: true

module Relaton
  module Sdo
    # A single organization name, optionally tagged with a language. A name with
    # no language is the default (untranslated) name.
    class Name
      attr_reader :content, :language

      def initialize(content:, language: nil)
        @content = content
        @language = language
      end

      def self.from_hash(hash)
        return new(content: hash) unless hash.is_a?(Hash)

        new(content: hash["content"], language: hash["language"])
      end

      def default?
        language.nil? || language.to_s.empty?
      end
    end
  end
end
