# frozen_string_literal: true

require "bundler/gem_tasks" # build / install / release for the `relaton` gem

# Each flavor's specs live in spec/<flavor>/ and run self-contained against the
# single gem (CWD = spec/<flavor> so their relative fixture/cassette/grammar
# paths resolve). `rake spec` runs them all; `rake spec:iso` runs one.
FLAVOR_SPECS = Dir["spec/*/"].map { |d| File.basename(d) }.sort.freeze

def run_flavor_spec(name)
  Dir.chdir("spec/#{name}") { system("bundle exec rspec -I . .") }
end

namespace :spec do
  FLAVOR_SPECS.each do |name|
    desc "Run spec/#{name}"
    task(name) { abort "spec/#{name} failed" unless run_flavor_spec(name) }
  end
end

desc "Run every flavor's spec suite"
task :spec do
  failed = FLAVOR_SPECS.reject do |name|
    puts "\n== spec/#{name} =="
    run_flavor_spec(name)
  end
  abort "\nFailed suites: #{failed.join(', ')}" unless failed.empty?
end

desc "Build the combined relaton gem + relaton-cli"
task :build_all do
  Rake::Task["build"].invoke # relaton (root gemspec)
  Bundler.with_unbundled_env do
    Dir.chdir("gems/relaton-cli") { sh "gem build *.gemspec" }
  end
end

task default: :spec
