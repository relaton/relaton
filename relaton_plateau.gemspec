# frozen_string_literal: true

require_relative "lib/relaton/plateau/version"

Gem::Specification.new do |spec|
  spec.name = "relaton-plateau"
  spec.version = Relaton::Plateau::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Relaton::Plateau: retrieve Project PLATEAU bibliographic " \
                 "items"
  spec.description = "Retrieve Project PLATEAU bibliographic items."

  spec.homepage = "https://github.com/relaton/relaton-plateau"
  spec.license = "BSD-2-Clause"

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")

  # spec.add_dependency "pubid", "~> 0.1.1"
  spec.add_dependency "base64"
  spec.add_dependency "relaton-index", "~> 0.2.12"
  spec.add_dependency "relaton-logger", "~> 0.2.0"
  spec.add_dependency "relaton-iso", "~> 2.0.0-alpha.2"
  spec.add_dependency "relaton-core", "~> 0.0.9"
end
