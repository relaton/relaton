module Relaton
  module Iso
    module Type
      # Lutaml-model attribute type that preserves `Pubid::Iso::Identifier`
      # instances on the way in and stringifies them on the way out.
      #
      # The default `:string` type calls `.to_s` during `cast`, which loses the
      # parsed structure and forces `Docidentifier#content=` to re-parse the
      # human-readable form. That round-trip can render dual-type strings
      # (e.g. `"ISO/IS TR 17"` from a TR pubid with stage 60.60) that the
      # pubid-iso parslet grammar can't capture cleanly, producing
      # `Duplicate subtrees while merging result of ROOT` warnings.
      class Pubid < Lutaml::Model::Type::Value
        def self.cast(value, _options = {})
          return nil if value.nil?
          return value if Lutaml::Model::Utils.uninitialized?(value)

          value
        end

        def self.serialize(value)
          return nil if value.nil?
          return value if Lutaml::Model::Utils.uninitialized?(value)

          value.to_s
        end

        def to_s
          value.to_s
        end

        def to_yaml
          value.to_s
        end

        def to_xml
          value.to_s
        end

        def to_json(*_args)
          value.to_s
        end

        def self.default_xsd_type
          "xs:string"
        end
      end
    end
  end
end
