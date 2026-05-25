# coding: utf-8

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "relaton/version"

Gem::Specification.new do |spec|
  spec.name          = "relaton"
  spec.version       = Relaton::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Relaton: bibliographic references to technical " \
                       "standards — database, registry, cache, and all " \
                       "flavor plugins bundled in one gem."
  spec.description   = <<~DESCRIPTION
    Relaton is the central database, registry, and cache for bibliographic
    references to technical standards in the Relaton/XML bibliographic
    model. It provides the Relaton::Db API, a plugin registry that lazily
    loads flavor gems (relaton-iso, relaton-ietf, etc.) on demand, and a
    file-based cache for fetched references.

    Installing this gem also pulls in every Relaton flavor plugin so you
    can fetch references from any supported standards body out of the
    box. The CLI (relaton-cli) is intentionally NOT a dependency —
    install it separately when you need command-line access.
  DESCRIPTION

  spec.homepage      = "https://github.com/relaton/relaton"
  spec.license       = "BSD-2-Clause"

  spec.bindir        = "bin"
  spec.require_paths = ["lib"]
  spec.files         = `git ls-files`.split("\n")
  spec.required_ruby_version = Gem::Requirement.new(">= 3.3.0")

  spec.add_dependency "relaton-bib", "~> 2.2.0"
  spec.add_dependency "relaton-core", "~> 2.2.0"
  spec.add_dependency "relaton-index", "~> 2.2.0"
  spec.add_dependency "relaton-logger", "~> 2.2.0"

  spec.add_dependency "relaton-3gpp", "~> 2.2.0"
  spec.add_dependency "relaton-bipm", "~> 2.2.0"
  spec.add_dependency "relaton-bsi", "~> 2.2.0"
  spec.add_dependency "relaton-calconnect", "~> 2.2.0"
  spec.add_dependency "relaton-ccsds", "~> 2.2.0"
  spec.add_dependency "relaton-cen", "~> 2.2.0"
  spec.add_dependency "relaton-cie", "~> 2.2.0"
  spec.add_dependency "relaton-doi", "~> 2.2.0"
  spec.add_dependency "relaton-ecma", "~> 2.2.0"
  spec.add_dependency "relaton-etsi", "~> 2.2.0"
  spec.add_dependency "relaton-gb", "~> 2.2.0"
  spec.add_dependency "relaton-iana", "~> 2.2.0"
  spec.add_dependency "relaton-iec", "~> 2.2.0"
  spec.add_dependency "relaton-ieee", "~> 2.2.0"
  spec.add_dependency "relaton-ietf", "~> 2.2.0"
  spec.add_dependency "relaton-iho", "~> 2.2.0"
  spec.add_dependency "relaton-isbn", "~> 2.2.0"
  spec.add_dependency "relaton-iso", "~> 2.2.0"
  spec.add_dependency "relaton-itu", "~> 2.2.0"
  spec.add_dependency "relaton-jis", "~> 2.2.0"
  spec.add_dependency "relaton-nist", "~> 2.2.0"
  spec.add_dependency "relaton-oasis", "~> 2.2.0"
  spec.add_dependency "relaton-ogc", "~> 2.2.0"
  spec.add_dependency "relaton-omg", "~> 2.2.0"
  spec.add_dependency "relaton-plateau", "~> 2.2.0"
  spec.add_dependency "relaton-un", "~> 2.2.0"
  spec.add_dependency "relaton-w3c", "~> 2.2.0"
  spec.add_dependency "relaton-xsf", "~> 2.2.0"

  spec.metadata["rubygems_mfa_required"] = "true"
end
