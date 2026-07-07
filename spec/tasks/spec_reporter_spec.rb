# frozen_string_literal: true

# Self-contained unit specs for the rake-spec reporter helper. No spec_helper /
# VCR needed — the module is pure. Run via `cd spec/tasks && rspec`, or through
# `rake spec` / `rake spec:tasks`.
require_relative "../../tasks/spec_reporter"

RSpec.describe SpecReporter do
  describe ".summary_line" do
    it "extracts the rspec summary line" do
      out = "....F.\n\nFailures:\n\n42 examples, 1 failure, 2 pending\n"
      expect(described_class.summary_line(out)).to eq "42 examples, 1 failure, 2 pending"
    end

    it "returns the last matching line when several are present" do
      out = "10 examples, 0 failures\n...\n3 examples, 1 failure\n"
      expect(described_class.summary_line(out)).to eq "3 examples, 1 failure"
    end

    it "returns nil when no summary line is present" do
      expect(described_class.summary_line("bundler: command not found: rspec\n")).to be_nil
      expect(described_class.summary_line("")).to be_nil
    end
  end

  describe ".format_duration" do
    it "renders sub-minute durations in seconds" do
      expect(described_class.format_duration(12.44)).to eq "12.4s"
      expect(described_class.format_duration(0.7)).to eq "0.7s"
    end

    it "renders minute-plus durations as m/s" do
      expect(described_class.format_duration(63)).to eq "1m03s"
      expect(described_class.format_duration(258)).to eq "4m18s"
    end
  end

  describe ".report" do
    def result(name:, passed:, summary:, output: "", seconds: 1.0)
      SpecReporter::Result.new(name: name, passed: passed, summary: summary,
                               output: output, seconds: seconds)
    end

    context "when a suite fails" do
      let(:results) do
        [
          result(name: "iso", passed: false,
                 summary: "321 examples, 3 failures",
                 output: "boom: expected ISO 123 got ISO 123:2001", seconds: 12.4),
          result(name: "bib", passed: true,
                 summary: "211 examples, 0 failures", seconds: 3.0),
          result(name: "nist", passed: false,
                 summary: "64 examples, 1 failure",
                 output: "nist detail here", seconds: 5.0),
        ]
      end

      let(:report) { described_class.report(results) }

      it "shows only the aggregate counts + total time, not a per-suite table" do
        expect(report).to include "1 passed, 2 failed"
        expect(report).to include "3 suites"
        # total time is the sum of the suites' seconds (12.4 + 3.0 + 5.0)
        expect(report).to include "20.4s"
        # the passing suites are NOT re-listed row-by-row (already streamed live)
        expect(report).not_to match(/PASS\s+spec\/bib/)
      end

      it "replays the captured output of only the failing suites" do
        expect(report).to include "FAILURE DETAILS: spec/iso"
        expect(report).to include "boom: expected ISO 123 got ISO 123:2001"
        expect(report).to include "FAILURE DETAILS: spec/nist"
        expect(report).to include "nist detail here"
      end

      it "names the failed suites and counts in the verdict" do
        expect(report).to match(/FAILED SUITES:.*spec\/iso.*spec\/nist/)
        expect(report).to include "1 passed, 2 failed"
        expect(report).to include "3 suites"
      end
    end

    context "when every suite passes" do
      let(:results) do
        [
          result(name: "bib", passed: true, summary: "211 examples, 0 failures", seconds: 3.0),
          result(name: "iso", passed: true, summary: "321 examples, 0 failures", seconds: 12.0),
        ]
      end

      it "shows just the all-passed counts, no failure or verdict sections" do
        report = described_class.report(results)
        expect(report).to include "2 passed, 0 failed"
        expect(report).to include "2 suites"
        expect(report).not_to include "FAILURE DETAILS"
        expect(report).not_to include "FAILED SUITES"
      end
    end
  end

  describe ".job_count" do
    it "defaults to nproc (capped by suite count) when the env is blank/nil" do
      expect(described_class.job_count(nil, 8, 35)).to eq 8
      expect(described_class.job_count("", 8, 35)).to eq 8
      expect(described_class.job_count("  ", 8, 35)).to eq 8
    end

    it "caps the default at the number of suites" do
      expect(described_class.job_count(nil, 16, 4)).to eq 4
    end

    it "honours an explicit JOBS value" do
      expect(described_class.job_count("4", 16, 35)).to eq 4
    end

    it "caps an explicit value above the suite count" do
      expect(described_class.job_count("50", 8, 35)).to eq 35
    end

    it "clamps zero / negative / garbage to a single job" do
      expect(described_class.job_count("0", 8, 35)).to eq 1
      expect(described_class.job_count("-3", 8, 35)).to eq 1
      expect(described_class.job_count("nope", 8, 35)).to eq 1
    end
  end

  describe ".run_suites" do
    it "returns results in input order regardless of completion order" do
      # Reverse-staggered sleeps: the first item finishes last.
      names = %w[a b c d]
      worker = lambda do |name|
        sleep((names.index(name) == 0 ? 0.05 : 0.001))
        "R:#{name}"
      end
      out = described_class.run_suites(names, jobs: 4, worker: worker)
      expect(out).to eq %w[R:a R:b R:c R:d]
    end

    it "actually runs workers concurrently when jobs > 1" do
      mutex = Mutex.new
      current = 0
      max = 0
      worker = lambda do |_name|
        mutex.synchronize { current += 1; max = [max, current].max }
        sleep 0.02
        mutex.synchronize { current -= 1 }
        :ok
      end
      described_class.run_suites(%w[a b c d e f], jobs: 3, worker: worker)
      expect(max).to eq 3
    end

    it "runs strictly sequentially when jobs is 1" do
      mutex = Mutex.new
      current = 0
      max = 0
      worker = lambda do |_name|
        mutex.synchronize { current += 1; max = [max, current].max }
        sleep 0.01
        mutex.synchronize { current -= 1 }
        :ok
      end
      described_class.run_suites(%w[a b c], jobs: 1, worker: worker)
      expect(max).to eq 1
    end

    it "invokes on_result once per suite" do
      seen = []
      described_class.run_suites(
        %w[a b c], jobs: 2,
        worker: ->(name) { "R:#{name}" },
        on_result: ->(r) { seen << r }
      )
      expect(seen.sort).to eq %w[R:a R:b R:c]
    end
  end
end
