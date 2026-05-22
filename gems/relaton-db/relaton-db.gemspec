# coding: utf-8

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "relaton/db/version"

Gem::Specification.new do |spec|
  spec.name          = "relaton-db"
  spec.version       = Relaton::Db::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Relaton database, registry and cache for " \
                       "bibliographic references to technical standards."
  spec.description   = <<~DESCRIPTION
    Relaton-db is the central database, registry, and cache for
    bibliographic references to technical standards in the Relaton/XML
    bibliographic model.

    It provides the Relaton::Db API, a plugin registry that lazily loads
    flavor gems (relaton-iso, relaton-ietf, etc.) on demand, and a
    file-based cache for fetched references.
  DESCRIPTION

  spec.homepage      = "https://github.com/relaton/relaton-db"
  spec.license       = "BSD-2-Clause"

  spec.bindir        = "bin"
  spec.require_paths = ["lib"]
  spec.files         = `git ls-files`.split("\n")
  spec.required_ruby_version = Gem::Requirement.new(">= 3.3.0")

  spec.add_dependency "relaton-bib", "~> 2.2"
  spec.add_dependency "relaton-core", "~> 2.2"
  spec.add_dependency "relaton-index", "~> 2.2"
  spec.add_dependency "relaton-logger", "~> 2.2"

  spec.metadata["rubygems_mfa_required"] = "true"
end
