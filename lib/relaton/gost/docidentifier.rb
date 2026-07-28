module Relaton
  module Gost
    # Structured GOST document identifier. The docid string is the
    # canonical citation form (e.g. "GOST R 34.12-2015", "GOST 14946-82").
    # Subclassed so future Pubid::Gost integration can hook in via
    # #pubid without changing the public interface.
    class Docidentifier < Bib::Docidentifier
    end
  end
end
