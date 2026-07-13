# frozen_string_literal: true

# Entry point for the single combined `relaton` gem. Each flavor namespace is
# autoloaded: referencing it (or any nested constant) the first time triggers
# `require "relaton/<flavor>"`, loading that flavor's code on demand rather than
# at `require "relaton"`. When adding a flavor, add an autoload line here.
require "relaton/version"

module Relaton
  autoload :Logger, "relaton/logger"
  autoload :Core, "relaton/core"
  autoload :Index, "relaton/index"
  autoload :Bib, "relaton/bib"
  autoload :ThreeGpp, "relaton/3gpp"
  autoload :Bipm, "relaton/bipm"
  autoload :Calconnect, "relaton/calconnect"
  autoload :Ccsds, "relaton/ccsds"
  autoload :Cen, "relaton/cen"
  autoload :Cie, "relaton/cie"
  autoload :Ecma, "relaton/ecma"
  autoload :Etsi, "relaton/etsi"
  autoload :Iana, "relaton/iana"
  autoload :Iala, "relaton/iala"
  autoload :Ieee, "relaton/ieee"
  autoload :Ietf, "relaton/ietf"
  autoload :Iho, "relaton/iho"
  autoload :Isbn, "relaton/isbn"
  autoload :Iso, "relaton/iso"
  autoload :Itu, "relaton/itu"
  autoload :Nist, "relaton/nist"
  autoload :Oasis, "relaton/oasis"
  autoload :Oiml, "relaton/oiml"
  autoload :Omg, "relaton/omg"
  autoload :Un, "relaton/un"
  autoload :W3c, "relaton/w3c"
  autoload :Xsf, "relaton/xsf"
  autoload :Bsi, "relaton/bsi"
  autoload :Gb, "relaton/gb"
  autoload :Iec, "relaton/iec"
  autoload :Jis, "relaton/jis"
  autoload :Ogc, "relaton/ogc"
  autoload :Plateau, "relaton/plateau"
  autoload :Doi, "relaton/doi"
  autoload :Sdo, "relaton/sdo"

  # Global PubID prefix register (relaton-db#103). Maps an SDO document-ID
  # prefix to the flavor module(s) that own it. Conflicting prefixes (e.g.
  # "ISO/IEC", claimed by both ISO and IEC) return several flavors.
  #
  #   Relaton.prefix_flavor("NIST")    # => [Relaton::Nist]
  #   Relaton.prefix_flavor("ISO/IEC") # => [Relaton::Iec, Relaton::Iso]
  #   Relaton.prefix_flavor("BOGUS")   # => []
  #
  # NOTE: returning the flavor module forces that flavor's lazy load. To resolve
  # a prefix without loading flavor code, use
  # `Relaton::Db::Registry.instance.processors_by_prefix(prefix)`.
  #
  # @param prefix [String]
  # @return [Array<Module>]
  def self.prefix_flavor(prefix)
    Db::Registry.instance.flavors_by_prefix(prefix)
  end

  # SDO organization & logo store (metanorma#346, relaton-db#132). Looks up a
  # standards body by abbreviation and returns its metadata — names/translations
  # and logo variants — from the `relaton-data-sdo` data repo. This is a
  # non-flavor store: no processor, no Db::Registry entry.
  #
  #   org = Relaton.organization("ISO")
  #   org.name                                   # default name
  #   org.name("fr")                             # translated name
  #   org.logo_query(format: "eps", style: "default")  # matching logo variants
  #   org.logo(format: "eps", style: "default")        # one logo
  #
  # @param abbreviation [String]
  # @return [Relaton::Sdo::Organization, nil]
  def self.organization(abbreviation)
    Sdo::Store.instance.organization(abbreviation)
  end
end

require "relaton/db"
