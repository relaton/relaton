# frozen_string_literal: true

require_relative "lib/relaton/oasis/version"

Gem::Specification.new do |spec|
  spec.name          = "relaton-oasis"
  spec.version       = Relaton::Oasis::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Relaton::Oasis: retrieve OASIS Standards for " \
                       "bibliographic use using the BibliographicItem model"
  spec.description   = "Relaton::Oasis: retrieve OASIS Standards for " \
                       "bibliographic use using the BibliographicItem model"
  spec.homepage      = "https://github.com/metanorma/relaton-oasis"
  spec.license       = "BSD-2-Clause"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.3.0")

  # spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ferrum", "~> 0.17"
  spec.add_dependency "mechanize", "~> 2.10"
  spec.add_dependency "multi_json", "~> 1.15.0"
  spec.add_dependency "relaton-bib", "~> 2.2.0"
  spec.add_dependency "relaton-core", "~> 2.2.0"
  spec.add_dependency "relaton-index", "~> 2.2.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
