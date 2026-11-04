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
  spec.executables   = ["relaton"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.3.0"

  # Explicit globs (the repo root holds more than the gem); grammar/ and spec/
  # are test-only and intentionally excluded. Per-flavor CLAUDE.md/README.adoc
  # sit in lib/relaton/<flavor>/ as dev docs and are excluded from the gem (the
  # root README.adoc still ships, added explicitly below).
  lib_docs = %w[CLAUDE.md README.adoc]
  spec.files = Dir.glob("lib/**/*") + Dir.glob("data/**/*.yaml")
                  .select { |f| File.file?(f) && !lib_docs.include?(File.basename(f)) } +
               Dir.glob("bin/**/*").select { |f| File.file?(f) } +
               %w[LICENSE README.adoc].select { |f| File.file?(f) }

  # Union of every flavor's external runtime dependencies (relaton-* siblings
  # are now internal). Conflicting pins reconciled to the tightest constraint.
  spec.add_dependency "addressable", "~> 2.8"
  spec.add_dependency "algolia", "~> 2.3.0"
  spec.add_dependency "base64", "~> 0.3"
  spec.add_dependency "bibtex-ruby", "~> 6.2"
  spec.add_dependency "cnccs", "~> 0.1.1"
  spec.add_dependency "concurrent-ruby", "~> 1.0"
  spec.add_dependency "sqlite3", "~> 2.10"
  spec.add_dependency "csv", "~> 3.3"
  spec.add_dependency "faraday", "~> 2.7"
  spec.add_dependency "faraday-net_http_persistent", "~> 2.0"
  spec.add_dependency "ferrum", "~> 0.17"
  spec.add_dependency "gb-agencies", "~> 0.0.1"
  spec.add_dependency "graphql", "~> 2.3"
  spec.add_dependency "graphql-client", "~> 0.23"
  spec.add_dependency "ieee-idams", "~> 0.3.0"
  spec.add_dependency "iso639", "~> 1.4"
  spec.add_dependency "isoics", "~> 0.1.6"
  spec.add_dependency "loc_mods", "~> 0.3.0"
  spec.add_dependency "logger", "~> 1.6"
  # Declared explicitly even though w3c_api pulls it in: lib/relaton/w3c rescues
  # Lutaml::Hal error classes by name, and ForbiddenError (403, the W3C
  # rate-limit signal) only exists from 0.2.5 — w3c_api's own `~> 0.2.1` would
  # happily resolve to an older one and NameError at rescue time.
  # 0.2.8 parses JSON bodies itself (yeptris) — the pin that dropped
  # json < 3 depends on it.
  spec.add_dependency "lutaml-hal", "~> 0.2.8"
  # singular_tolerance (relaton#301) requires 0.8.113 (lutaml-model#971);
  # 0.8.107-112 raise on the stricter collection validation instead.
  spec.add_dependency "lutaml-model", "~> 0.8.113"
  # 0.3.2 fixes the FileSystem adapter defects the Db cache depends on:
  # lossless keys, thread and process exclusion, DatabaseStore serialization,
  # CacheStore#each_key (lutaml/lutaml-store#17).
  spec.add_dependency "lutaml-store", "~> 0.3.2"
  spec.add_dependency "htmlentities"
  spec.add_dependency "twitter_cldr"
  spec.add_dependency "liquid", "~> 5"
  spec.add_dependency "thor"
  spec.add_dependency "thor-hollaback"

  spec.add_dependency "mechanize", "~> 2.10"
  spec.add_dependency "mini_portile2", "~> 2.8.0"
  spec.add_dependency "niso-jats", "~> 0.3.4"
  spec.add_dependency "moxml", "~> 0.6.0"
  spec.add_dependency "leptris", "~> 1.9.391"
  spec.add_dependency "parallel", "~> 1.26"
  # Numeric capture editions (ruby#361): 1.3.114 records the artifact
  # edition as the integer 2 and carries the edition-2 whitespace-class
  # glue fix, and pubid 2.0.0.pre.alpha.65 re-bakes every artifact at it
  # and requires >= 1.3.114. A runtime older than the release rejects the
  # numeric edition it does not implement, so the floor names 1.3.114
  # for bundles that depend on relaton.
  # parsanol's bind-coverage check (added in 1.3.127 for
  # parsanol-ruby#427, BS 9113 raw-bound captures) looks for the capture
  # name among the bound keys, not the binding's path leaf, so every
  # capture bound under another name raises BindError — all of
  # Pubid::Oiml.parse ("doc_number" -> "number"). 1.3.127/1.3.128 shipped
  # broken and fresh resolutions of the old `~> 1.3.124` floor picked
  # them up (relaton#439); 1.3.129 carries the fix (parsanol-ruby#435)
  # and drops artifact edition 1, so the floor names the fixed line and
  # the interim cap is lifted.
  spec.add_dependency "parsanol", "~> 1.3.129" # the mode-alias removal floor; pubid 2.0.4 artifacts require >= 1.3.124
  # 2.0.4 carries the IHO series identity components (year/volume/issue,
  # pubid#635/#637) that the relaton-data-iho re-key (relaton#407) keys on;
  # a runtime older than the release rejects the components it does not
  # implement. 2.0.5 re-bakes every artifact at parsanol edition 2 — the
  # IHO component-model wave (relaton#440) — and parsanol 1.3.129+
  # rejects edition-1 artifacts, so the floor names 2.0.5 beside the
  # parsanol floor.
  spec.add_dependency "pubid", "~> 2.0.5"

  # JSON parse/generate across the flavor fetchers, the index and the db:
  # yeptris's strict RFC 8259 surface replaces the stdlib json gem's calls.
  # The boundary parser needs the allow_duplicate_key: opt-out, which
  # 0.6.51.0 carries (yeptris-ruby#339, published 2026-10-30).
  spec.add_dependency "yeptris", "~> 0.6.51"
  spec.add_dependency "rfcxml", "~> 0.4.3"
  spec.add_dependency "rubyzip", "~> 3.7"
  # 0.3.3 is the floor, not a preference: it sets an identifying User-Agent
  # (a bare Faraday one trips Cloudflare's bot heuristics on api.w3.org) and
  # makes its 403 retry actually fire. See lib/relaton/w3c/CLAUDE.md.
  spec.add_dependency "w3c_api", "~> 0.3.3"

  spec.metadata["rubygems_mfa_required"] = "true"
end
