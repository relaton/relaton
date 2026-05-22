# frozen_string_literal: true

require_relative "lib/relaton/doi/version"

Gem::Specification.new do |spec|
  spec.name          = "relaton-doi"
  spec.version       = Relaton::Doi::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "RelatonDOI: retrieve Standards for bibliographic " \
                       "using DOI through Crossrefand provide Relaton object."
  spec.description   = "RelatonDOI: retrieve Standards for bibliographic " \
                       "using DOI through Crossrefand provide Relaton object."
  spec.homepage      = "https://github.com/relaton/relaton-doi"
  spec.license       = "BSD-2-Clause"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.3.0")

  # spec.metadata["allowed_push_host"] = "TODO: Set to 'https://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  # spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  spec.add_dependency "relaton-bib", "~> 2.2"
  spec.add_dependency "relaton-bipm", "~> 2.2"
  spec.add_dependency "relaton-ieee", "~> 2.2"
  spec.add_dependency "relaton-ietf", "~> 2.2"
  spec.add_dependency "relaton-nist", "~> 2.2"
  # spec.add_dependency "relaton-w3c", "~> 2.2"
  spec.add_dependency "mechanize", "~> 2.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
