module Relaton
  module Sae
    #
    # The SAE codes a Crossref DOI names.
    #
    # SAE deposits one DOI per edition, and its suffix is SAE's own edition
    # code in lowercase: `10.4271/j3016_202104` is `SAE J3016_202104`, the
    # April 2021 edition of J3016. Aerospace standards are told apart by a
    # revision letter instead and carry no date (`10.4271/ams4121j`).
    #
    # Three strings come out of it:
    #
    # * `#native` — the code in the DOI's spelling (`SAE AMSQQA250/4B`). The
    #   output file is named after it, so a file name never depends on pubid.
    # * `#printed` — the code as SAE prints it (`SAE AMS-QQ-A-250/4B`), the
    #   document's primary identifier.
    # * `#reference` — the form the index row is parsed from. It is the
    #   native code when the DOI has a date; an undated code gets the year of
    #   the record's approval date, so a dated reference also reaches an
    #   aerospace revision (`SAE AMS4121J:2017`).
    #
    class DoiCode
      PREFIX = "10.4271/".freeze
      # A code, then an optional `_YYYYMM` edition date. The code takes letters,
      # digits, the `/` of a part (`j2337/2`) and any `_` that is not that date
      # (`as5259/7a_a1`, `j1939da_4q2012`: 1,163 of the 2026-11 deposits); what
      # it means is pubid's business, so nothing else is decided here.
      SUFFIX = %r{\A(?<code>[a-z0-9][a-z0-9/._-]*?)(?:_(?<date>\d{6}))?\z}i

      attr_reader :code, :date, :year

      #
      # @param doi [String, nil] e.g. `10.4271/j3016_202104`
      # @param approved_year [String, Integer, nil] the record's approval year
      # @return [Relaton::Sae::DoiCode, nil] nil for a DOI that is not SAE's
      #
      def self.parse(doi, approved_year: nil)
        suffix = doi.to_s.strip
        return unless suffix.downcase.start_with? PREFIX

        match = SUFFIX.match suffix[PREFIX.size..]
        return unless match

        new(match[:code].upcase, match[:date], approved_year)
      end

      def initialize(code, date, approved_year)
        @code = code
        @date = date
        @year = date ? date[0, 4] : approved_year&.to_s
      end

      # @return [String] SAE's edition code, e.g. `SAE J3016_202104`
      def native
        date ? "SAE #{code}_#{date}" : "SAE #{code}"
      end

      # @return [String] the code SAE prints, or the native code when pubid
      #   cannot read it
      def printed
        pubid&.to_s || native
      end

      # @return [String] the reference the index row is parsed from
      def reference
        return native if date || !year

        "SAE #{code}:#{year}"
      end

      # @return [Pubid::Sae::Identifier, nil] the native code, parsed
      def pubid
        return @pubid if defined? @pubid

        @pubid = begin
          ::Pubid::Sae::Identifier.parse native
        rescue ::Pubid::Errors::Error, ArgumentError
          nil
        end
      end
    end
  end
end
