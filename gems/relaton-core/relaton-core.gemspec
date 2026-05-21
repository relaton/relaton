lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "relaton/core/version"

Gem::Specification.new do |spec|
  spec.name          = "relaton-core"
  spec.version       = Relaton::Core::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.homepage      = "https://github.com/relaton/relaton-core"
  spec.summary       = "Library for importing and caching bibliographic references to technical standards"
  spec.description   = "Library for importing and caching bibliographic references to technical standards"
  spec.license       = "BSD-2-Clause"

  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").select do |f|
      f.match(%r{^(lib|exe)/}) || f.match(%r{\.yaml$})
    end
  end
  spec.extra_rdoc_files = %w[README.adoc LICENSE.txt]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = Gem::Requirement.new(">= 3.1.0")

  spec.add_dependency "nokogiri", ">= 1.16"
  spec.add_dependency "psych", "~> 5.2.0" # versin 5.3.0 crashes
  spec.add_dependency "relaton-logger", "~> 0.2.0"
  # spec.add_dependency "relaton-bib", "~> 1.20.0"
  # spec.add_dependency "relaton-index", "~> 0.2.16"
  # spec.add_dependency "pubid-core", "~> 1.12.10"
end
