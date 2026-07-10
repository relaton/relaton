# relaton-cli is released in lockstep with the combined `relaton` gem from this
# repo. Derive the version (and the relaton dependency pin) from the single
# source of truth — root lib/relaton/version.rb — so `gem bump` on that one file
# re-stamps both gems. No separate version to hand-sync.
root_version_file = File.expand_path("../../lib/relaton/version.rb", __dir__)
relaton_version = File.read(root_version_file)[/VERSION\s*=\s*["']([^"']+)["']/, 1] or
  raise "could not parse Relaton::VERSION from #{root_version_file}"

Gem::Specification.new do |spec|
  spec.name          = "relaton-cli"
  spec.version       = relaton_version
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Relaton Command-line Interface"
  spec.description   = "Relaton Command-line Interface"
  spec.homepage      = "https://github.com/metanorma/relaton-cli"
  spec.license       = "BSD-2-Clause"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features|docs)/})
  end
  spec.extra_rdoc_files = %w[docs/README.adoc LICENSE]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = Gem::Requirement.new(">= 3.3.0")

  spec.add_dependency "liquid", "~> 5"
  # The CLI requires "parslet" directly to rescue Parslet::ParseFailed when a
  # reference is unparseable (see command.rb / subcommand_collection.rb). It is
  # already a runtime dep of `relaton`, but declare it here too so the require
  # is self-supporting rather than dependent on relaton's transitive graph.
  spec.add_dependency "parslet", "~> 2.0.0"
  # relaton bundles every flavor plus Relaton::Bib, so depending on `relaton`
  # alone is sufficient — relaton-bib is no longer published standalone.
  spec.add_dependency "relaton", "= #{relaton_version}"
  spec.add_dependency "thor"
  spec.add_dependency "thor-hollaback"
end
