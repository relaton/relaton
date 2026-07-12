module Relaton
  module Adobe
    # Structured Adobe document identifier. The docid string is the
    # canonical form (e.g. "Adobe Technical Note #5014", "Adobe Glyph
    # List"). Defined as a subclass so future Pubid::Adobe integration
    # can hook in via #pubid without changing the public interface.
    class Docidentifier < Bib::Docidentifier
    end
  end
end
