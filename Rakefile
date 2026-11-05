# frozen_string_literal: true

require "bundler/gem_tasks" # build / install / release for the `relaton` gem
require "etc" # Etc.nprocessors — default worker count for parallel `rake spec`
require_relative "tasks/spec_reporter"

# Each flavor's specs live in spec/<flavor>/ and run self-contained against the
# single gem (CWD = spec/<flavor> so their relative fixture/cassette/grammar
# paths resolve). `rake spec` runs them all; `rake spec:iso` runs one. Only dirs
# that actually hold a *_spec.rb are suites (skips e.g. spec/vcr_cassettes/).
#
# spec/corpus is the identifier-model property suite: it downloads every
# flavor's full published index and takes minutes per flavor, so it is a
# scheduled conformance job (`rake spec:corpus`), not part of the per-PR matrix.
CORPUS_SPECS = %w[corpus].freeze
FLAVOR_SPECS = Dir["spec/*/"]
  .select { |d| !Dir.glob("#{d}**/*_spec.rb").empty? }
  .map { |d| File.basename(d) }
  .reject { |name| CORPUS_SPECS.include?(name) }
  # spec/cli and spec/render ship their own spec_helpers and run through
  # spec:cli / spec:render after the parallel flavor run, not through it.
  .reject { |name| %w[cli render].include?(name) }
  .sort.freeze

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

  # Refresh the OGC suite's offline index. Copies the whole published index
  # (~1,258 rows) and converts each string id to its pubid hash — see
  # tasks/index_fixture_ogc.rb for why it is not curated.
  desc "Refresh spec/ogc/fixtures/index-v2.zip from relaton-data-ogc"
  task :update_index_ogc do
    require_relative "tasks/index_fixture_ogc"
    require_relative "lib/relaton/ogc"
    # Named from INDEXFILE, so the next index version bump moves the fixture
    # with it instead of silently writing the old name.
    path = "spec/ogc/fixtures/#{Relaton::Ogc::INDEXFILE}.zip"
    count = IndexFixtureOgc.build(path)
    puts "Wrote #{count} rows to #{path}"
  end

  # Refresh the XSF suite's offline index. Copies the whole published index and
  # converts each string id to its pubid hash — see tasks/index_fixture_xsf.rb
  # for the two non-document rows it drops.
  desc "Refresh spec/xsf/fixtures/index-v2.zip from relaton-data-xsf"
  task :update_index_xsf do
    require_relative "tasks/index_fixture_xsf"
    require_relative "lib/relaton/xsf"
    path = "spec/xsf/fixtures/#{Relaton::Xsf::INDEXFILE}.zip"
    count = IndexFixtureXsf.build(path)
    puts "Wrote #{count} rows to #{path}"
  end

  # Refresh the ECMA suite's offline index. Copies the whole published index
  # (804 rows) verbatim — see tasks/index_fixture_ecma.rb for why it is not
  # curated.
  desc "Refresh spec/ecma/fixtures/index-v2.zip from relaton-data-ecma"
  task :update_index_ecma do
    require_relative "tasks/index_fixture_ecma"
    require_relative "lib/relaton/ecma"
    # Named from INDEXFILE, so the next index version bump moves the fixture
    # with it instead of silently writing the old name.
    path = "spec/ecma/fixtures/#{Relaton::Ecma::INDEXFILE}.zip"
    count = IndexFixtureEcma.build(path)
    puts "Wrote #{count} rows to #{path}"
  end

  # Refresh the CalConnect suite's offline index. Copies the whole published
  # index (191 rows) verbatim — see tasks/index_fixture_calconnect.rb for why it
  # is not curated.
  desc "Refresh spec/calconnect/fixtures/index-v2.zip from relaton-data-calconnect"
  task :update_index_calconnect do
    require_relative "tasks/index_fixture_calconnect"
    require_relative "lib/relaton/calconnect"
    # Named from INDEXFILE, so the next index version bump moves the fixture
    # with it instead of silently writing the old name.
    path = "spec/calconnect/fixtures/#{Relaton::Calconnect::INDEXFILE}.zip"
    count = IndexFixtureCalconnect.build(path)
    puts "Wrote #{count} rows to #{path}"
  end

  # Refresh the OASIS suite's offline index. Copies the whole published index
  # (605 rows) verbatim — see tasks/index_fixture_oasis.rb for why it is not
  # curated.
  desc "Refresh spec/oasis/fixtures/index-v2.zip from relaton-data-oasis"
  task :update_index_oasis do
    require_relative "tasks/index_fixture_oasis"
    require_relative "lib/relaton/oasis"
    # Named from INDEXFILE, so the next index version bump moves the fixture
    # with it instead of silently writing the old name.
    path = "spec/oasis/fixtures/#{Relaton::Oasis::INDEXFILE}.zip"
    count = IndexFixtureOasis.build(path)
    puts "Wrote #{count} rows to #{path}"
  end

  # The identifier-model conformance job (docs/identifier-model.adoc). Runs
  # against each flavor's FULL published corpus, which means network access and
  # minutes of parsing; keep it out of the per-PR matrix. CORPUS=nist,oasis
  # narrows the run.
  desc "Run the corpus property suite (full published corpora; network)"
  task :corpus do
    abort "spec:corpus failed" unless run_flavor_spec("corpus")
  end

  # The relaton-cli and relaton-render suites moved into spec/cli and
  # spec/render and ride the root bundle: both codebases ship inside the
  # relaton gem (lib/relaton/cli, lib/relaton/render).
  desc "Run the relaton CLI spec suite"
  task :cli do
    # Own spec_helper: the root .rspec pulls the flavor suites' helper,
    # which the CLI suite does not use.
    sh "bundle exec rspec --require ./spec/cli/spec_helper spec/cli"
  end

  desc "Run the relaton-render spec suite"
  task :render do
    sh "bundle exec rspec --require ./spec/render/spec_helper spec/render"
  end

  # Rebuild the relaton CLI's frontend bundle (Vite -> dist). The dist is
  # committed so the gem build needs no Node; refresh it whenever
  # lib/relaton/cli/frontend/src changes and commit the result.
  front_dir = File.expand_path("lib/relaton/cli/frontend", __dir__)
  desc "Build the relaton CLI frontend bundle into lib/relaton/cli/frontend/dist"
  task :build_frontend do
    Dir.chdir(front_dir) do
      sh "npm ci"
      sh "npm run build"
    end
  end

  # Everything: the parallel flavor run, then relaton-cli. Rake::Task[...] looks
  # up by full name from root, so "spec" is the top-level flavor task (not
  # spec:spec). Fails fast — the flavor task aborts on red before cli runs.
  desc "Run every flavor suite (parallel) then the cli and render suites"
  task :all do
    Rake::Task["spec"].invoke
    Rake::Task["spec:cli"].invoke
    Rake::Task["spec:render"].invoke
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

desc "Build the relaton gem (ships lib/relaton/cli and its committed frontend dist)"
task :build_all do
  Rake::Task["build"].invoke
end

task default: "spec:all"
