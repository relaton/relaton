# frozen_string_literal: true

Dir["./support/**/*.rb"].sort.each { |f| require f }

require "relaton/doi"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.expose_dsl_globally = true
end

def read_fixture(file)
  File.read("fixtures/#{file}", encoding: "UTF-8")
    .gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}(?=<\/fetched>)/, Date.today.to_s)
end

def write_fixture(file, xml)
  path = "fixtures/#{file}"
  File.write(path, xml, encoding: "UTF-8") unless File.exist? path
end
