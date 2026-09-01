# frozen_string_literal: true

require "bundler/gem_tasks" # build / install / release for the `relaton` gem
require "etc" # Etc.nprocessors — default worker count for parallel `rake spec`
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
# SpecReporter::Result. Uses IO.popen's `chdir:` spawn option instead of
# Dir.chdir so it is thread-safe (Dir.chdir mutates process-global CWD) — the
# parallel runner calls this from worker threads. VERBOSE output is printed as a
# grouped block by the on_result callback in :spec, not streamed here.
def capture_flavor_spec(name)
  output = +""
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  IO.popen("bundle exec rspec -I . .", chdir: "spec/#{name}",
                                       err: %i[child out]) do |io|
    io.each_line { |line| output << line }
  end
  ok = $?.success? # $? is thread-local, so this is safe under the pool
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  SpecReporter::Result.new(
    name: name, passed: ok, output: output, seconds: elapsed,
    summary: SpecReporter.summary_line(output)
  )
rescue StandardError => e
  # The worker MUST NOT raise (run_suites joins in creation order, so one raise
  # would leak the other threads and drop their results). Infra failures — e.g.
  # rspec/bundle not spawnable — become a failed Result so the run reports.
  SpecReporter::Result.new(
    name: name, passed: false, output: "#{e.class}: #{e.message}",
    seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
    summary: nil
  )
end

namespace :spec do
  FLAVOR_SPECS.each do |name|
    desc "Run spec/#{name}"
    task(name) { abort "spec/#{name} failed" unless run_flavor_spec(name) }
  end

  # Refresh the 3GPP suite's offline index. Cuts a curated subset from the
  # published index and converts each id to its pubid hash — see
  # tasks/index_fixture_3gpp.rb for what each document group is for.
  desc "Refresh spec/3gpp/fixtures/index-v2.zip from relaton-data-3gpp"
  task :update_index_3gpp do
    require_relative "tasks/index_fixture_3gpp"
    require_relative "lib/relaton/3gpp"
    # Named from INDEXFILE, so the next index version bump moves the fixture
    # with it instead of silently writing the old name.
    path = "spec/3gpp/fixtures/#{Relaton::ThreeGpp::INDEXFILE}.zip"
    count = IndexFixture3gpp.build(path)
    puts "Wrote #{count} rows to #{path}"
  end

  # relaton-cli is the one separate gem (own Gemfile/lock, gem "relaton",
  # path: "../.."), so run its suite in its OWN bundle — with_unbundled_env +
  # cd, the same shape as build_all. bundle check || install first so it works
  # on a fresh checkout; sh aborts on non-zero so a red cli suite fails the task.
  desc "Run the relaton-cli gem's spec suite (its own bundle)"
  task :cli do
    Bundler.with_unbundled_env do
      Dir.chdir("gems/relaton-cli") do
        sh "bundle check || bundle install"
        sh "bundle exec rake spec"
      end
    end
  end

  # Everything: the parallel flavor run, then relaton-cli. Rake::Task[...] looks
  # up by full name from root, so "spec" is the top-level flavor task (not
  # spec:spec). Fails fast — the flavor task aborts on red before cli runs.
  desc "Run every flavor suite (parallel) then the relaton-cli suite"
  task :all do
    Rake::Task["spec"].invoke
    Rake::Task["spec:cli"].invoke
  end
end

desc "Run every flavor's spec suite in parallel " \
     "(JOBS=N sets workers, JOBS=1 = sequential; VERBOSE=1 dumps each suite)"
task :spec do
  jobs = SpecReporter.job_count(ENV["JOBS"], Etc.nprocessors,
                                FLAVOR_SPECS.length)
  puts "Running #{FLAVOR_SPECS.length} flavor suites across #{jobs} job(s) " \
       "(JOBS=N to change, VERBOSE=1 to dump each suite)...\n\n"

  # Suites finish out of order under the pool, so print a full status line per
  # suite as it completes (guarded by the runner's mutex), and — with VERBOSE —
  # its whole captured output as one grouped block (no interleaving).
  on_result = lambda do |result|
    status = result.passed ? "PASS" : "FAIL"
    summary = result.summary || "no examples run"
    puts "  #{"spec/#{result.name}".ljust(22)} ... #{status}  " \
         "(#{summary})  [#{SpecReporter.format_duration(result.seconds)}]"
    print result.output if ENV["VERBOSE"]
  end

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  results = SpecReporter.run_suites(
    FLAVOR_SPECS, jobs: jobs,
    worker: method(:capture_flavor_spec), on_result: on_result
  )
  wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

  puts SpecReporter.report(results)
  puts "  wall: #{SpecReporter.format_duration(wall)} " \
       "(across #{jobs} job(s))"
  abort unless results.all?(&:passed)
end

desc "Build the combined relaton gem + relaton-cli"
task :build_all do
  Rake::Task["build"].invoke # relaton (root gemspec)
  Bundler.with_unbundled_env do
    Dir.chdir("gems/relaton-cli") do
      # Compile the frontend into frontend/dist so the gemspec can ship it.
      sh "bundle exec rake build_frontend"
      sh "gem build *.gemspec"
    end
  end
end

task default: :spec
