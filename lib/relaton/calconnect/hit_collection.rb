module Relaton::Calconnect
  class HitCollection < Relaton::Core::HitCollection
    GHURL = "https://raw.githubusercontent.com/relaton/relaton-data-calconnect/refs/heads/v2/".freeze

    # @param ref [Strig]
    # @param year [String]
    def initialize(ref, year = nil)
      super
      # INDEXFILE_V1, not INDEXFILE: relaton-data-calconnect publishes no
      # index-v2.zip yet. The consumer commit points this at INDEXFILE, adds
      # `pubid_class:`, and passes a parsed pubid rather than the ref string —
      # `Type#search_candidates` narrows only for a non-String, so the two have
      # to change together. See lib/relaton/calconnect/CLAUDE.md.
      index = Relaton::Index.find_or_create :CC, url: "#{GHURL}#{INDEXFILE_V1}.zip",
                                                 file: "#{INDEXFILE_V1}.yaml"
      @array = index.search(ref).map do |row|
        Hit.new(row, self)
      end
    end
  end
end
