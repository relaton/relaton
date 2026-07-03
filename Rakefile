# frozen_string_literal: true

require "bundler/gem_tasks" # build / install / release for the `relaton` gem
require_relative "tasks/spec_reporter"

# Each flavor's specs live in spec/<flavor>/ and run self-contained against the
# single gem (CWD = spec/<flavor> so their relative fixture/cassette/grammar
# paths resolve). `rake spec` runs them all; `rake spec:iso` runs one. Only dirs
# that actually hold a *_spec.rb are suites (skips e.g. spec/vcr_cassettes/).
FLAVOR_SPECS = Dir["spec/*/"]
  .select { |d| !Dir.glob("#{d}**/*_spec.rb").empty? }
  .map { |d| File.basename(d) }.sort.freeze

# Single-flavor runs stream live output (already scannable when debugging one).
def run_flavor_spec(name)
  Dir.chdir("spec/#{name}") { system("bundle exec rspec -I . .") }
end

# Run one flavor capturing its combined output + wall-clock time, returning a
# SpecReporter::Result. With VERBOSE, also stream the raw output live.
def capture_flavor_spec(name)
  verbose = ENV["VERBOSE"]
  output = +""
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ok = Dir.chdir("spec/#{name}") do
    IO.popen("bundle exec rspec -I . .", err: %i[child out]) do |io|
      io.each_line { |line| output << line; print line if verbose }
    end
    $?.success?
  end
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  SpecReporter::Result.new(
    name: name, passed: ok, output: output, seconds: elapsed,
    summary: SpecReporter.summary_line(output)
  )
end

namespace :spec do
  FLAVOR_SPECS.each do |name|
    desc "Run spec/#{name}"
    task(name) { abort "spec/#{name} failed" unless run_flavor_spec(name) }
  end
end

desc "Run every flavor's spec suite (VERBOSE=1 streams raw output)"
task :spec do
  puts "Running #{FLAVOR_SPECS.length} flavor suites " \
       "(VERBOSE=1 to stream raw output)...\n\n"
  results = FLAVOR_SPECS.map do |name|
    print "  #{"spec/#{name}".ljust(22)} ... "
    $stdout.flush
    result = capture_flavor_spec(name)
    status = result.passed ? "PASS" : "FAIL"
    summary = result.summary || "no examples run"
    puts "#{status}  (#{summary})  [#{SpecReporter.format_duration(result.seconds)}]"
    result
  end
  puts SpecReporter.report(results)
  abort unless results.all?(&:passed)
end

desc "Build the combined relaton gem + relaton-cli"
task :build_all do
  Rake::Task["build"].invoke # relaton (root gemspec)
  Bundler.with_unbundled_env do
    Dir.chdir("gems/relaton-cli") { sh "gem build *.gemspec" }
  end
end

task default: :spec
