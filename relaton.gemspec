# coding: utf-8
  
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "relaton/version"

Gem::Specification.new do |spec|
  spec.name          = "relaton"
  spec.version       = Relaton::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "gem for importing and caching bibliographic references to technical standards"
  spec.description   = <<~DESCRIPTION
  gem for importing and caching bibliographic references to technical standards
  in the Relaton/XML bibliographic model.

  This gem is in active development.
  DESCRIPTION

  spec.homepage      = "https://github.com/riboseinc/relaton"
  spec.license       = "BSD-2-Clause"

  spec.bindir        = "bin"
  spec.require_paths = ["lib"]
  spec.files         = `git ls-files`.split("\n")
  spec.test_files    = `git ls-files -- {spec}/*`.split("\n")
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.add_dependency "algoliasearch"
  spec.add_dependency "gbbib", "~> 0.3.0"
  spec.add_dependency "isobib", "~> 0.3.0"
  spec.add_dependency "rfcbib", "~> 0.3.0"
  spec.add_dependency 'iso-bib-item', '~> 0.3.0'

  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "byebug", "~> 10.0"
  spec.add_development_dependency "equivalent-xml", "~> 0.6"
  spec.add_development_dependency "guard", "~> 2.14"
  spec.add_development_dependency "guard-rspec", "~> 4.7"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "rspec", "~> 3.6"
  spec.add_development_dependency "rubocop", "~> 0.50"
  spec.add_development_dependency "simplecov", "~> 0.15"
  spec.add_development_dependency "timecop", "~> 0.9"
end
