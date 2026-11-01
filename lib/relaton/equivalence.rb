require "yeptris/psych"

module Relaton
  # Cross-SDO equivalence as data: chain patterns and explicit equivalences
  # the resolver consults when a reference misses. Tables are YAML files
  # (schema: data/equivalence/adoption-chains.yaml); the gem ships the seed
  # table and callers register more with {.register}.
  module Equivalence
    class << self
      # @return [Array<Hash>] loaded tables, innermost last
      def tables
        @tables ||= []
      end

      # Register a table file or every *.yaml under a directory. Later
      # registrations take precedence (checked first).
      #
      # @param [String] path file or directory
      # @return [Array<Hash>] the tables now loaded
      def register(path)
        files = if File.directory?(path)
                  Dir.glob(File.join(path, "*.yaml")).sort.reverse
                else
                  [path]
                end
        files.each { |f| tables << Yeptris::Psych.safe_load_file(f, aliases: true) }
        tables
      end

      # Load the gem's seed table (idempotent). {Db} calls this on first use.
      def load_seed
        register(seed_path) unless tables.any?
        tables
      end

      def seed_path
        File.join(__dir__, "..", "..", "data", "equivalence", "adoption-chains.yaml")
      end

      # Reset (spec seam).
      def reset!
        @tables = nil
      end

      # The canonical reference for `code`, or nil when no table maps it.
      # The code itself is not returned: a miss on a canonical form stays a
      # miss.
      #
      # @param [String] code
      # @return [String, nil]
      def canonical_for(code)
        load_seed
        tables.each do |table|
          (table["equivalences"] || []).each do |eq|
            next if eq["canonical"] == code
            next unless Array(eq["equivalents"]).include?(code)

            return eq["canonical"]
          end
          (table["chains"] || []).each do |chain|
            m = Regexp.new(chain["match"]).match(code)
            next unless m

            chain["resolve"].each do |template|
              candidate = template.gsub(/\\(\d+)/) { m[Regexp.last_match(1).to_i] }
              return candidate unless candidate == code
            end
          end
        end
        nil
      end

      # Every equivalent of `code`, canonical form first, the code itself
      # excluded.
      #
      # @param [String] code
      # @return [Array<String>]
      def equivalents_for(code)
        out = []
        cursor = code
        while (next_code = canonical_for(cursor)) && !out.include?(next_code)
          out << next_code
          cursor = next_code
        end
        out
      end

      # Every edge of `code`'s equivalence set: the canonical walk
      # (.equivalents_for — a national adoption falls back to the EN, the EN
      # to the ISO) PLUS the reverse edges, generated from the tables'
      # `adoptions` ladders (the ISO resolves to its EN, BS EN, DIN EN and
      # NF EN adoptions). The code itself is excluded; the walk order is
      # canonical-first, ladder outermost-last.
      #
      # @param [String] code
      # @return [Array<String>]
      def related_for(code)
        out = equivalents_for(code)
        load_seed
        ([code] + out.uniq).each do |candidate|
          tables.each do |table|
            (table["adoptions"] || []).each do |ladder|
              m = Regexp.new(ladder["pattern"]).match(candidate)
              next unless m

              Array(ladder["forms"]).each do |template|
                form = template.gsub(/\\(\d+)/) { m[Regexp.last_match(1).to_i] }
                out << form unless form == code || out.include?(form)
              end
            end
          end
        end
        out
      end
    end
  end
end
