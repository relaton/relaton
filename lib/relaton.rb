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
end

require "relaton/db"
