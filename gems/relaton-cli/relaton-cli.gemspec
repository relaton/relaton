# Compatibility shell for the retired standalone relaton-cli gem: the CLI
# implementation was consolidated into the relaton gem (lib/relaton/cli),
# which this release pulls as its single runtime dependency. Version is
# literal and independent now — it only needs to sort above the last real
# relaton-cli release (3.0.7) so existing bundles co-resolve cleanly.
Gem::Specification.new do |spec|
  spec.name          = "relaton-cli"
  spec.version       = "3.1.0"
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Relaton Command-line Interface (superseded by the relaton gem)"
  spec.description   = "Compatibility shell: the Relaton CLI now ships inside the relaton gem."
  spec.homepage      = "https://github.com/relaton/relaton"
  spec.license       = "BSD-2-Clause"

  spec.files         = %w[lib/relaton-cli.rb LICENSE CHANGELOG.md]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.3.0"

  # Generous on purpose: the shell must co-resolve with whatever modern
  # relaton a bundle already carries — a tight floor here would leave the
  # shell unresolvable until that exact relaton release exists.
  spec.add_dependency "relaton", ">= 3.0.7", "< 5"
end
