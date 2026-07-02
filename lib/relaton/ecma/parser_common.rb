module Relaton
  module Ecma
    module ParserCommon
      def default_bib_hash
        {
          type: "standard", language: ["en"], script: ["Latn"], place: [Bib::Place.new(city: "Geneva")]
        }
      end

      def contributor
        orgname = Bib::TypedLocalizedString.new(content: "Ecma International", language: "en", script: "Latn")
        org = Bib::Organization.new name: [orgname]
        role = Bib::Contributor::Role.new type: "publisher"
        [Bib::Contributor.new(organization: org, role: [role])]
      end

      # @return [Array<Relaton::Bib::Docidentifier>]
      def fetch_docidentifier(id = nil)
        return [] if id.nil? || id.empty?

        [Bib::Docidentifier.new(type: "ECMA", content: id, primary: true)]
      end

      def fetch_ext
        Ext.new(doctype: fetch_doctype, flavor: "ecma")
      end

      def fetch_doctype
        Bib::Doctype.new content: "document"
      end
    end
  end
end
