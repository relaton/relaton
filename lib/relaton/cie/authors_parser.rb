module Relaton
  module Cie
    # CIE publishes its author lists as one inconsistently formatted string:
    # "Surname, I.X." pairs, bare "Forename Surname" runs, Chinese-style
    # "Surname Given" without a comma, compound surnames ("Nilsson
    # Tengelin"), broken hyphens ("Dam- Hansen"), " and " before the final
    # author, and "et al." tails (relaton-cie#5). The comma is overloaded --
    # it separates authors and marks the surname/forename boundary -- so the
    # parse walks comma-separated segments with three rules:
    #
    # 1. a single-word segment binds the following segment as its forenames
    #    ("Hemphälä, Hillevi"; initials "A.Sh." bind the same way);
    # 2. a multi-word segment followed by an initials-only segment binds
    #    them ("Nilsson Tengelin, M."), because initials never stand alone;
    # 3. any other segment is one author kept whole (completename) --
    #    "Glimne Susanne", "Annika K. Jägerbrand", "Pan Jiangen": which word
    #    is the surname would be a guess, so none is made.
    module AuthorsParser
      Author = Struct.new(:surname, :forenames, :completename)

      # Uppercase-led, dot/hyphen/space-separated short parts only:
      # "A.Sh.", "H.T.B", "W-T. M.", "N." -- never "Li" (lowercase tail),
      # "Guillaume" (long undotted part) or "Bierman".
      INITIALS_RX = /\A\p{Lu}(?:[.\s-]+\p{Lu}\p{Ll}{0,2})*\.?\z/.freeze

      class << self
        # @param string [String] the CIE authors string
        # @return [Array<Author>]
        def parse(string)
          authors = []
          segments = segmentize(string)
          i = 0
          while i < segments.length
            seg = segments[i]
            nxt = segments[i + 1]
            i += if initials?(seg)
                   # Defensive: a stray initials segment binds left.
                   authors.last&.forenames << seg
                   1
                 elsif single_word?(seg) || nxt && initials?(nxt)
                   # "Surname, Forename": a single-word segment binds
                   # whatever follows; a multi-word one only binds trailing
                   # initials, which never stand alone.
                   authors << Author.new(seg, nxt ? [nxt] : [], nil)
                   nxt ? 2 : 1
                 else
                   authors << Author.new(nil, nil, seg)
                   1
                 end
          end
          authors
        end

        # @param seg [String]
        # @return [Boolean]
        def single_word?(seg)
          !seg.include?(" ")
        end

        # @param seg [String]
        # @return [Boolean]
        def initials?(seg)
          INITIALS_RX.match? seg
        end

        private

        def segmentize(string)
          string
            .gsub(/(\p{L})- (?=\p{Lu})/, '\1-')
            .gsub(%r{\s*,?\s+and\s+}i, ", ")
            .sub(/\s*,?\s*et\s+al\.?\s*\z/i, "")
            .split(/\s*[,;]\s*/).map(&:strip).reject(&:empty?)
        end
      end
    end
  end
end
