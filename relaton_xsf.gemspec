# frozen_string_literal: true

require_relative "lib/relaton/xsf/version"

Gem::Specification.new do |spec|
  spec.name = "relaton-xsf"
  spec.version = Relaton::Xsf::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Relaton::Xsf: retrieve ISO Standards for bibliographic use " \
                 "using the IsoBibliographicItem model"
  spec.description = "Relaton::Xsf: retrieve ISO Standards for bibliographic use " \
                     "using the IsoBibliographicItem model"
  spec.homepage = "https://github.com/relaton/relaton-xsf"
  spec.license = "BSD-2-Clause"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")

  # spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  # spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  spec.add_dependency "mechanize", "~> 2.10"
  spec.add_dependency "relaton-bib", "~> 2.1.0"
  spec.add_dependency "relaton-core", "~> 0.0.13"
  spec.add_dependency "relaton-index", "~> 0.2.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
