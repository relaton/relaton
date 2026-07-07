# frozen_string_literal: true

# Pure helpers for the `rake spec` runner: parse rspec output and format the
# final report. No I/O here so the logic is unit-testable without running the
# real suites (see spec/tasks/spec_reporter_spec.rb). Lives under tasks/ (not
# lib/) so it is never packaged into the gem.
module SpecReporter
  # One flavor suite's outcome. `output` is the captured combined stdout/stderr;
  # `summary` is the extracted rspec summary line; `seconds` is wall-clock time.
  Result = Struct.new(:name, :passed, :summary, :output, :seconds,
                      keyword_init: true)

  RULE = "=" * 72
  BANNER = "━" * 60

  # The rspec summary line, e.g. "42 examples, 1 failure, 2 pending".
  # Returns the last match (the real total sits after any per-file noise), or
  # nil when the suite produced none (crash, no rspec, empty dir).
  def self.summary_line(output)
    output.to_s.lines.reverse_each.find do |line|
      line.match?(/\d+ examples?, \d+ failures?/)
    end&.strip
  end

  # Resolve the worker-pool size for `rake spec` from the JOBS env value.
  # Blank/nil -> nproc; an explicit int is honoured; the result is clamped to
  # 1..max(suite_count, 1) (garbage / <1 -> 1, over-large -> suite_count). Pure.
  def self.job_count(env_value, nproc, suite_count)
    requested = env_value.to_s.strip
    n = requested.empty? ? nproc.to_i : requested.to_i
    n = 1 if n < 1
    [n, [suite_count, 1].max].min
  end

  # Run `names` through `worker` (a callable taking one name) using a bounded
  # pool of up to `jobs` threads. `worker.call` runs OUTSIDE any lock, so the
  # suites run truly concurrently; each result is stored and `on_result` (if
  # given) invoked UNDER a mutex, so status lines / verbose blocks print
  # atomically. Returns results in the original `names` order. No I/O of its own
  # (the caller supplies `on_result`) so it stays unit-testable.
  #
  # Contract: `worker` MUST NOT raise — it runs on a pool thread joined in
  # creation order, so a raise would leak the remaining threads and drop their
  # results. Workers own their error handling (capture_flavor_spec rescues into
  # a failed Result).
  def self.run_suites(names, jobs:, worker:, on_result: nil)
    queue = Queue.new
    names.each { |n| queue << n }
    results = {}
    mutex = Mutex.new
    pool = [[jobs, names.length].min, 1].max
    Array.new(pool) do
      Thread.new do
        loop do
          name = begin
            queue.pop(true)
          rescue ThreadError
            break
          end
          res = worker.call(name)
          mutex.synchronize do
            results[name] = res
            on_result&.call(res)
          end
        end
      end
    end.each(&:join)
    names.map { |n| results[n] }
  end

  # Compact human duration: "0.7s", "12.4s", "1m03s".
  def self.format_duration(seconds)
    seconds = seconds.to_f
    return format("%.1fs", seconds) if seconds < 60

    mins = (seconds / 60).to_i
    secs = (seconds - mins * 60).round
    format("%dm%02ds", mins, secs)
  end

  # The final report string: a one-line aggregate count (the per-suite status
  # already streamed live while running), then the captured output of only the
  # failing suites, then a verdict naming them.
  def self.report(results)
    failed = results.reject(&:passed)
    total_time = format_duration(results.sum { |r| r.seconds.to_f })

    lines = ["", RULE, verdict_counts(results, failed, total_time), RULE]

    unless failed.empty?
      failed.each { |r| lines.concat(failure_details(r)) }
      names = failed.map { |r| "spec/#{r.name}" }.join(", ")
      lines.push("", RULE, " FAILED SUITES: #{names}", RULE)
    end
    lines.join("\n") + "\n"
  end

  # --- internals -----------------------------------------------------------

  def self.verdict_counts(results, failed, total_time)
    passed = results.length - failed.length
    format("  %d passed, %d failed  (%d suites, %s total)",
           passed, failed.length, results.length, total_time)
  end
  private_class_method :verdict_counts

  def self.failure_details(result)
    ["", "━━━ FAILURE DETAILS: spec/#{result.name} #{BANNER}",
     result.output.to_s.rstrip]
  end
  private_class_method :failure_details
end
