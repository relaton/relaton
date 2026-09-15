module Relaton
  module Omg
    # An OMG document identifier backed by `Pubid::Omg`.
    #
    # `content` stays a plain string, so serialization is unchanged; the parsed
    # identifier lives beside it in `@pubid` and drives the mutators. Follows
    # the IALA and CEN shape (`lib/relaton/iala/docidentifier.rb`,
    # `lib/relaton/cen/model/docidentifier.rb`).
    class Docidentifier < Bib::Docidentifier
      # @return [Pubid::Omg::Identifier, nil] nil when the content is not an
      #   OMG identifier, or the grammar cannot read it
      attr_reader :pubid

      # Capture the inherited (LocalizedMarkedUpString) content setter before
      # overriding #content=, so #refresh_content! writes the re-rendered string
      # back WITHOUT re-parsing it and discarding the mutation.
      alias_method :store_content, :content=

      def content=(value)
        super
        return unless value

        @pubid = begin
          # `pubid` is required lazily because deserialization reaches this
          # class without the flavor entry file having been loaded. LoadError
          # degrades to a plain string; StandardError covers a non-OMG value
          # and a title the grammar rejects, both of which are DATA and must
          # not raise. A malformed *query* raises — see Scraper.scrape_page.
          require "pubid"
          ::Pubid::Omg::Identifier.parse(value)
        rescue LoadError, StandardError
          nil
        end
      end

      # OMG identifiers carry no date. The version is OMG's discriminator
      # (`OMG AMI4CCM 1.0` and `OMG AMI4CCM 1.1` are two editions of one
      # specification), so the version-agnostic ("most recent") reference drops
      # the version — as IALA maps `remove_date!` onto its edition.
      def remove_date!
        return unless @pubid

        replace_pubid @pubid.exclude(:version)
      end

      # The part is the volume or format segment after the version, e.g.
      # `Superstructure` in `OMG UML 2.1.1 Superstructure`.
      def remove_part!
        return unless @pubid

        replace_pubid @pubid.exclude(:part)
      end

      # `to_all_parts!` stays the inherited no-op. An OMG part is a volume or a
      # format name, not a numbered part, so there is no "all parts" form.

      private

      # `Pubid#exclude` returns a COPY, so the new identifier replaces the old
      # one.
      def replace_pubid(new_pubid)
        @pubid = new_pubid
        store_content @pubid.to_s
      end
    end
  end
end
