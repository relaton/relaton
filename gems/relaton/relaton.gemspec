# coding: utf-8

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "relaton/version"

Gem::Specification.new do |spec|
  spec.name          = "relaton"
  spec.version       = Relaton::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Relaton meta-gem: relaton-db plus all flavor plugins."
  spec.description   = <<~DESCRIPTION
    Convenience meta-gem that installs the Relaton database (relaton-db)
    and every Relaton flavor plugin in one go. Useful for users who want
    to fetch references from any supported standards body without
    cherry-picking gems.

    The CLI (relaton-cli) is intentionally NOT a dependency — install it
    separately when you need command-line access.
  DESCRIPTION

  spec.homepage      = "https://github.com/relaton/relaton"
  spec.license       = "BSD-2-Clause"

  spec.require_paths = ["lib"]
  spec.files         = `git ls-files`.split("\n")
  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")

  spec.add_dependency "relaton-db", "~> 2.1"

  spec.add_dependency "relaton-3gpp", "~> 2.1"
  spec.add_dependency "relaton-bipm", "~> 2.1"
  spec.add_dependency "relaton-bsi", "~> 2.1"
  spec.add_dependency "relaton-calconnect", "~> 2.1"
  spec.add_dependency "relaton-ccsds", "~> 2.1"
  spec.add_dependency "relaton-cen", "~> 2.1"
  spec.add_dependency "relaton-cie", "~> 2.1"
  spec.add_dependency "relaton-doi", "~> 2.1"
  spec.add_dependency "relaton-ecma", "~> 2.1"
  spec.add_dependency "relaton-etsi", "~> 2.1"
  spec.add_dependency "relaton-gb", "~> 2.1"
  spec.add_dependency "relaton-iana", "~> 2.1"
  spec.add_dependency "relaton-iec", "~> 2.1"
  spec.add_dependency "relaton-ieee", "~> 2.1"
  spec.add_dependency "relaton-ietf", "~> 2.1"
  spec.add_dependency "relaton-iho", "~> 2.1"
  spec.add_dependency "relaton-isbn", "~> 2.1"
  spec.add_dependency "relaton-iso", "~> 2.1"
  spec.add_dependency "relaton-itu", "~> 2.1"
  spec.add_dependency "relaton-jis", "~> 2.1"
  spec.add_dependency "relaton-nist", "~> 2.1"
  spec.add_dependency "relaton-oasis", "~> 2.1"
  spec.add_dependency "relaton-ogc", "~> 2.1"
  spec.add_dependency "relaton-omg", "~> 2.1"
  spec.add_dependency "relaton-plateau", "~> 2.1"
  spec.add_dependency "relaton-un", "~> 2.1"
  spec.add_dependency "relaton-w3c", "~> 2.1"
  spec.add_dependency "relaton-xsf", "~> 2.1"

  spec.metadata["rubygems_mfa_required"] = "true"
end
