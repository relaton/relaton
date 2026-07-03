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

      it "lists every suite in the summary table with PASS/FAIL and timing" do
        expect(report).to match(/FAIL\s+spec\/iso.*321 examples, 3 failures/)
        expect(report).to match(/PASS\s+spec\/bib.*211 examples, 0 failures/)
        expect(report).to include "12.4s"
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

      it "reports all suites passed and includes no failure-details section" do
        report = described_class.report(results)
        expect(report).to include "All 2 suites passed"
        expect(report).not_to include "FAILURE DETAILS"
        expect(report).not_to include "FAILED SUITES"
      end
    end
  end
end
