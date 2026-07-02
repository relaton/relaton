module Relaton
  module Oiml
    # OIML document types, per relaton/relaton-oiml#1. The value is carried in
    # the inherited `content` attribute (e.g. `recommendation`). `bulletin`
    # (the online OIML Bulletin) is listed for forward-compatibility; the
    # dataset does not yet contain such records. The list is intentionally not
    # enforced as an enum so unforeseen dataset values still round-trip.
    class Doctype < Bib::Doctype
      TYPES = %w[recommendation document guide vocabulary basic-publication
                 expert-report seminar-report translation bulletin].freeze
    end
  end
end
