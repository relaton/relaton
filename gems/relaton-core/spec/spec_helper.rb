# frozen_string_literal: true

require "bundler/setup"
require "rspec/matchers"
require "simplecov"

SimpleCov.start do
  add_filter "/spec/"
end

require_relative "../lib/relaton-core"

Dir["./spec/support/**/*.rb"].sort.each { |f| require f }
