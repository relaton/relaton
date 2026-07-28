module Relaton
  module Easc
    # Structured EASC document identifier. The docid string is the
    # canonical citation form (e.g. "ПМГ 03-2025", "РМГ 151-2025").
    # Subclassed so future Pubid::Easc integration can hook in via
    # #pubid without changing the public interface.
    class Docidentifier < Bib::Docidentifier
    end
  end
end
