# frozen_string_literal: true

require_relative "lib/relaton/cen/version"

Gem::Specification.new do |spec|
  spec.name          = "relaton-cen"
  spec.version       = Relaton::Cen::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Relaton::Cen: retrieve Cenelec Standards for " \
                       "bibliographic use using the IsoBibliographicItem model"
  spec.description   = "Relaton::Cen: retrieve Cenelec Standards for " \
                       "bibliographic use using the IsoBibliographicItem model"
  spec.homepage      = "https://github.com/metanorma/relaton-cen"
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

  spec.add_dependency "isoics", "~> 0.1"
  spec.add_dependency "mechanize", "~> 2.10"
  spec.add_dependency "relaton-core", "~> 2.2"
  spec.add_dependency "relaton-bib", "~> 2.2"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
