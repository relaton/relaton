module Relaton
  module Bib
    class Docidentifier < LocalizedMarkedUpString
      attribute :type, :string
      attribute :scope, :string
      attribute :primary, :boolean

      xml do
        root "docidentifier"
        map_attribute "type", to: :type
        map_attribute "scope", to: :scope
        map_attribute "primary", to: :primary
      end

      key_value do
        map "type", to: :type
        map "scope", to: :scope
        map "primary", to: :primary
      end

      # `Bib::ItemData#to_all_parts` and `#to_most_recent_reference` broadcast
      # these three to EVERY docidentifier unconditionally, so raising here made
      # both calls unusable for any flavor that had not subclassed this class —
      # 13 of them had not, and both died on every item they produced. The raise
      # was also `NotImplementedError`, which descends from `ScriptError`, so a
      # caller's `rescue => e` did not even catch it.
      #
      # The default is therefore a **no-op**. An identifier that models neither
      # a part nor a date has nothing to strip, and returning it unchanged is
      # the correct answer for both calls.
      #
      # A flavor whose identifier does carry one overrides these — see
      # `Relaton::Ogc::Docidentifier` or `Relaton::Iala::Docidentifier` for the
      # pubid-backed shape (parse `content` into a pubid, mutate, re-render
      # through a `store_content` alias so the write does not re-parse).
      #
      # The trade-off, recorded so it stays a choice rather than an oversight: a
      # flavor that DOES carry a date but has not overridden `remove_date!` now
      # returns a dated reference silently, where before it crashed loudly.
      # That is a missing override in the flavor, not a defect here.

      def remove_part!; end

      def to_all_parts!; end

      def remove_date!; end

      # Docidentifier types with an SDO-specific :external and :internal form
      # (relaton#49), mapped to the pubid flavor that renders both. The
      # :external form carries the publisher ("IETF RFC 8341",
      # "BSI PAS 2031:2019"); the :internal form is the one the SDO uses for its
      # own documents, without it ("SP 800-113" for "NIST SP 800-113"). pubid
      # decides per identifier, so "BS EN ISO 8848:2021" and "CGPM RES (1889)"
      # are the same in both forms. Every other type answers its content for
      # both forms: pubid would drop "ISO" from an ISO identifier.
      #
      # The table keys on `type`, not on a flavor subclass, so it also covers a
      # relation's nested `Bib::ItemData` and the `Bib::Docidentifier` objects
      # BIPM and IETF build (a subclass-typed collection would make lutaml's
      # YAML serializer reject those).
      FORM_PUBID = {
        "NIST" => :Nist,
        "BIPM" => :Bipm,
        "IETF" => :Ietf,
        "Internet-Draft" => :Ietf,
        "BSI" => :Bsi,
      }.freeze

      # The :slug form's type → pubid flavor map (relaton#441): every
      # docidentifier type whose pubid flavor has a landed pubid-scheme
      # URN schema (pubid#656). Unlike FORM_PUBID — which gates only the
      # SDO publisher forms and stays deliberately small — this table
      # grows with the pubid URN coverage: the slug is the lossless
      # pubid-scheme URN in path clothes, so there is no publisher-form
      # policy in the decision, only "can this flavor emit a
      # round-trippable slug". Every row was verified end-to-end at
      # adoption: parse → Pubid.to_slug → Pubid.from_slug → equal hash.
      # A type absent here degrades to the stored content.
      SLUG_PUBID = {
        "ISO" => :Iso,
        "IEC" => :Iec,
        "IEEE" => :Ieee,
        "IHO" => :Iho,
        "ITU-T" => :Itu,
        "ITU-R" => :Itu,
        "ITU" => :Itu,
        "W3C" => :W3c,
        "3GPP" => :Tgpp,
        "OGC" => :Ogc,
        "OASIS" => :Oasis,
        "OMG" => :Omg,
        "UN" => :Un,
        "XEP" => :Xsf,
        "EVS" => :Evs,
        "CCSDS" => :Ccsds,
        "CEN" => :CenCenelec,
        "BIPM" => :Bipm,
        "CalConnect" => :Calconnect,
        "ECMA" => :Ecma,
        "GB" => :Gb,
        "IANA" => :Iana,
        "NIST" => :Nist,
        "BSI" => :Bsi,
        "IETF" => :Ietf,
        "Internet-Draft" => :Ietf,
        "GOST" => :Gost,
        "JCGM" => :Jcgm,
        "OIML" => :Oiml,
        "SAE" => :Sae,
        "IALA" => :Iala,
        "EASC" => :Easc,
        "DOI" => :Doi,
        "ISBN" => :Isbn,
        "JIS" => :Jis,
      }.freeze

      FORMS = %i[external internal slug].freeze

      # The parsed identifier. A pubid-backed flavor subclass overrides it.
      def pubid; end

      # @param form [Symbol, nil] nil for the stored content, :external for the
      #   identifier with its publisher, :internal for the form the SDO uses
      #   for its own documents
      # @raise [ArgumentError] for an unknown form
      def to_s(form: nil)
        return content.to_s unless form

        form = form.to_sym
        unless FORMS.include?(form)
          raise ArgumentError, "unknown identifier form: #{form.inspect}"
        end

        form_content(form).to_s
      end

      private

      # pubid renders the form (`to_s(with_publisher:)`, pubid#620); the
      # :slug form renders through the flavor's pubid-scheme URN schema.
      # A docidentifier with a parsed pubid (a flavor subclass) uses it;
      # a plain `Bib::Docidentifier` is parsed through the form's flavor
      # table — FORM_PUBID for the publisher forms, SLUG_PUBID for :slug
      # (relaton#441). Content pubid cannot parse is returned unchanged.
      def form_content(form)
        flavor = form == :slug ? SLUG_PUBID[type] : FORM_PUBID[type]
        # :slug takes a parsed pubid from anywhere — the slug is the
        # pubid-scheme URN, publisher policy plays no part in it. The
        # publisher forms keep the FORM_PUBID gate: a type outside the
        # table answers its stored content (relaton#49), even when a
        # subclass carries a parsed pubid.
        id =
          if form == :slug
            pubid || (flavor && parse_form_pubid(flavor))
          else
            flavor && (pubid || parse_form_pubid(flavor))
          end
        return content unless id

        return slug_form(id) if form == :slug

        id.to_s(with_publisher: form == :external)
      end

      # The pubid-scheme slug (relaton#441): the URN in HTTP-path
      # clothes, bijective with Pubid.from_slug. A flavor whose
      # pubid-scheme schema has not landed yet degrades to the stored
      # content, like a form pubid cannot parse.
      def slug_form(id)
        require "pubid"
        ::Pubid.to_slug(id)
      rescue ::Pubid::Errors::InvalidInputError, NameError
        content
      end

      def parse_form_pubid(flavor)
        return if content.to_s.empty?

        require "pubid"
        ::Pubid.const_get(flavor).parse(content)
      rescue StandardError
        nil
      end
    end
  end
end
