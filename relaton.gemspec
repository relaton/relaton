# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "relaton/version"

Gem::Specification.new do |spec|
  spec.name          = "relaton"
  spec.version       = Relaton::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Relaton: bibliographic references to technical " \
                       "standards — database, registry, cache, and every " \
                       "flavor in one gem."
  spec.description   = <<~DESCRIPTION
    Relaton is the database, registry, and cache for bibliographic references
    to technical standards in the Relaton/XML bibliographic model. It provides
    the Relaton::Db API, a registry that lazily loads each standards-body
    flavor (ISO, IETF, NIST, IEC, …) on first use, and a file-based cache.

    Every flavor ships inside this single gem — `gem install relaton` gives you
    the full multi-flavor setup, with flavor code loaded on demand via autoload.
    The CLI (relaton-cli) is a separate gem.
  DESCRIPTION

  spec.homepage      = "https://github.com/relaton/relaton"
  spec.license       = "BSD-2-Clause"

  spec.bindir        = "bin"
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.3.0"

  # Explicit globs (the repo root holds more than the gem); grammar/ and spec/
  # are test-only and intentionally excluded. Per-flavor CLAUDE.md files sit in
  # lib/relaton/<flavor>/ as dev docs and are excluded from the packaged gem.
  spec.files = Dir.glob("lib/**/*")
                  .select { |f| File.file?(f) && File.basename(f) != "CLAUDE.md" } +
               Dir.glob("bin/**/*").select { |f| File.file?(f) } +
               %w[LICENSE README.adoc].select { |f| File.file?(f) }

  # Union of every flavor's external runtime dependencies (relaton-* siblings
  # are now internal). Conflicting pins reconciled to the tightest constraint.
  spec.add_dependency "addressable", "~> 2.8"
  spec.add_dependency "algolia", "~> 2.3.0"
  spec.add_dependency "base64", ">= 0"
  spec.add_dependency "bibtex-ruby", ">= 0"
  spec.add_dependency "cnccs", "~> 0.1.1"
  spec.add_dependency "concurrent-ruby", "~> 1.0"
  spec.add_dependency "csv", "~> 3.3"
  spec.add_dependency "faraday", "~> 2.7.0"
  spec.add_dependency "faraday-net_http_persistent", "~> 2.0"
  spec.add_dependency "ferrum", "~> 0.17"
  spec.add_dependency "gb-agencies", "~> 0.0.1"
  spec.add_dependency "graphql", "~> 2.3"
  spec.add_dependency "graphql-client", "~> 0.23"
  spec.add_dependency "ieee-idams", "~> 0.3.0"
  spec.add_dependency "iso639", ">= 0"
  spec.add_dependency "isoics", "~> 0.1.6"
  spec.add_dependency "loc_mods", "~> 0.3.0"
  spec.add_dependency "logger", "~> 1.6"
  spec.add_dependency "lutaml-model", "~> 0.8.0"
  spec.add_dependency "mechanize", "~> 2.10"
  spec.add_dependency "mini_portile2", "~> 2.8.0"
  spec.add_dependency "niso-jats", "~> 0.3.4"
  spec.add_dependency "nokogiri", ">= 1.16"
  spec.add_dependency "openssl", "~> 3.3.2"
  spec.add_dependency "parallel", "~> 1.26"
  spec.add_dependency "parslet", "~> 2.0.0"
  spec.add_dependency "psych", "~> 5.2.0"
  spec.add_dependency "pubid", "~> 2.0.0.pre.alpha.3"
  spec.add_dependency "rfcxml", "~> 0.4.3"
  spec.add_dependency "rubyzip", "~> 2.3.0"
  spec.add_dependency "w3c_api", "~> 0.3.2"

  spec.metadata["rubygems_mfa_required"] = "true"
end
