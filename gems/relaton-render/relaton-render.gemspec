# Compatibility shell for the retired standalone relaton-render gem: the
# citation renderer was consolidated into the relaton gem (lib/relaton/render).
# Version is literal and independent — it only needs to sort above the last
# real relaton-render release (3.0.0).
Gem::Specification.new do |spec|
  spec.name          = "relaton-render"
  spec.version       = "3.0.1"
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Relaton citation rendering (superseded by the relaton gem)"
  spec.description   = "Compatibility shell: Relaton citation rendering now ships inside the relaton gem."
  spec.homepage      = "https://github.com/relaton/relaton"
  spec.license       = "BSD-2-Clause"

  spec.files         = %w[lib/relaton-render.rb LICENSE]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.3.0"

  # Generous on purpose: the shell must co-resolve with whatever modern
  # relaton a bundle already carries.
  spec.add_dependency "relaton", ">= 3.0.7", "< 5"
end
