# frozen_string_literal: true

module Relaton
  module Sdo
    # A standards-development organization: its names (with translations) and its
    # logo variants. Built from one entry of the index manifest.
    class Organization
      attr_reader :abbreviation, :names, :logos

      def initialize(abbreviation:, names: [], logos: [])
        @abbreviation = abbreviation
        @names = names
        @logos = logos
      end

      def self.from_hash(abbreviation, hash)
        hash ||= {}
        new(
          abbreviation: abbreviation,
          names: Array(hash["name"]).map { |n| Name.from_hash(n) },
          logos: Array(hash["logo"]).map { |l| Logo.from_hash(l) },
        )
      end

      # The organization's name. With no argument (or a nil language) returns the
      # default, untranslated name; otherwise the translation for the requested
      # language — passed positionally (`name("fr")`) or as the `language:`
      # keyword (`name(language: "fr")`) — or nil if there is none. The keyword
      # wins if both are given.
      def name(lang = nil, language: nil)
        language ||= lang
        selected =
          if language.nil?
            names.find(&:default?) || names.first
          else
            names.find { |n| n.language == language }
          end
        selected&.content
      end

      # All logo variants matching the given filters. Every argument is optional;
      # omitting one matches any value for it. Returns an array (possibly empty).
      def logo_query(format: nil, size: nil, style: nil)
        logos.select do |logo|
          match?(logo.format, format) &&
            match?(logo.size, size) &&
            match?(logo.style, style)
        end
      end

      # A single logo matching the filters. Returns nil when nothing matches; the
      # sole match when exactly one does; raises when the filter is ambiguous so
      # the caller narrows it by format/size/style.
      def logo(format: nil, size: nil, style: nil)
        matches = logo_query(format: format, size: size, style: style)
        return matches.first if matches.size <= 1

        raise Error, "#{matches.size} logos match #{abbreviation}; narrow by " \
                     "format/size/style: #{matches.map(&:describe).join('; ')}"
      end

      private

      def match?(value, query)
        return true if query.nil?

        !value.nil? && value.to_s.casecmp?(query.to_s)
      end
    end
  end
end
