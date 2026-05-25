# frozen_string_literal: true

require_relative "lib/relaton/ccsds/version"

Gem::Specification.new do |spec|
  spec.name         = "relaton-ccsds"
  spec.version      = Relaton::Ccsds::VERSION
  spec.authors      = ["Ribose Inc."]
  spec.email        = ["open.source@ribose.com"]

  spec.summary      = "Relaton::Ccsds: retrive www.ccsds.org Standards"
  spec.description  = "Relaton::Ccsds: retrive www.ccsds.org Standards"
  spec.homepage     = "https://github.com/metanorma/relaton-ccsds"
  spec.license      = "MIT"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{^(test|spec|features)/})
    end
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = Gem::Requirement.new(">= 3.3.0")

  # Uncomment to register a new dependency of your gem
  spec.add_dependency "csv", "~> 3.3"
  spec.add_dependency "mechanize", "~> 2.10"
  spec.add_dependency "openssl", "~> 3.3.2"
  spec.add_dependency "pubid", "~> 2.0.0.pre.alpha.1"
  spec.add_dependency "relaton-bib", "~> 2.2.0"
  spec.add_dependency "relaton-core", "~> 2.2.0"
  spec.add_dependency "relaton-index", "~> 2.2.0"
  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
