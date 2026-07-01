# frozen_string_literal: true

# Single spec helper shared by every flavor suite. Each suite runs from its own
# spec/<flavor>/ dir (`cd spec/<flavor> && rspec`), and its .rspec adds `-I ..`
# so the `--require spec_helper` there resolves to this file.
#
# Anything flavor-specific (VCR/WebMock config, index fixtures, the umbrella's
# eager-load) lives in that flavor's own spec/<flavor>/support/*.rb, auto-loaded
# below. This file holds only what is common to all suites.

require "bundler/setup"
require_relative "simplecov_env" # start coverage before any app code loads
require "rspec/matchers"
require "equivalent-xml"
require "jing"
require "net/http" # used by some fetcher specs (e.g. gb)
require "yaml"

# Per-flavor support: CWD is spec/<flavor>/, so this globs THAT flavor's support
# dir (VCR/WebMock config, index-fixture before(:suite) hooks, umbrella setup).
Dir["./support/**/*.rb"].sort.each { |f| require f }

# Load the flavor under test, inferred from the suite directory name. Every
# flavor maps spec/<flavor> -> relaton/<flavor>; the umbrella (spec/relaton)
# drives Relaton::Db instead.
flavor = File.basename(Dir.pwd)
require flavor == "relaton" ? "relaton/db" : "relaton/#{flavor}"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`, but keep the
  # bare describe/it DSL available.
  config.disable_monkey_patching!
  config.expose_dsl_globally = true

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# Fixture read/write helpers used by the bsi/cen/cie/doi/ecma suites (each
# formerly defined its own copy in its per-flavor spec_helper). Top-level so
# examples can call them bare; other flavors' write_file/read_file references
# are receiver methods on the flavor classes under test, unaffected by these.

def replace_date(xml)
  xml.gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s)
end

def write_file(file, content)
  File.write file, content, encoding: "UTF-8" unless File.exist? file
end

def read_file(file)
  replace_date File.read(file, encoding: "UTF-8")
end

# alias read_file uses, kept as a distinct name the bsi/cen suites call
def read_xml(file)
  replace_date File.read(file, encoding: "UTF-8")
end

# doi keeps its own fixtures/ prefix + <fetched>…</fetched>-anchored replace
def read_fixture(file)
  File.read("fixtures/#{file}", encoding: "UTF-8")
    .gsub(%r{(?<=<fetched>)\d{4}-\d{2}-\d{2}(?=</fetched>)}, Date.today.to_s)
end

def write_fixture(file, xml)
  path = "fixtures/#{file}"
  File.write(path, xml, encoding: "UTF-8") unless File.exist? path
end
