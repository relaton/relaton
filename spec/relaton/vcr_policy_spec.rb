# frozen_string_literal: true

# Cassettes never auto-rerecord (relaton#360): a re-record is a deliberate,
# local act. This guards every VCR config in the repo — each flavor suite, this
# umbrella suite and relaton-cli — so a copied config cannot bring back a
# `re_record_interval` that rewrites cassettes on CI.
RSpec.describe "VCR cassette policy" do
  root = File.expand_path("../..", __dir__)
  files = Dir[File.join(root, "{spec,gems/relaton-cli/spec}/**/*.rb")] -
    [File.expand_path(__FILE__)]
  rel = ->(path) { path.delete_prefix("#{root}/") }

  # Any assignment of the option, in any syntax: `re_record_interval: x`,
  # `:re_record_interval => x`, `[:re_record_interval] = x`.
  assignment = /re_record_interval(?::|\s*=>|\]\s*=)\s*([^,\s#)]+)/
  configs = files.select { |f| File.read(f).include?("VCR.configure") }

  it "finds every suite's VCR config" do
    expect(configs.size).to be >= 31
    expect(configs.map(&rel)).to include(
      "spec/relaton/support/umbrella.rb", "gems/relaton-cli/spec/support/vcr.rb"
    )
  end

  configs.each do |path|
    it "sets re_record_interval to nil in #{rel[path]}" do
      expect(File.read(path).scan(assignment).flatten).to eq ["nil"]
    end
  end

  it "sets no other re_record_interval in a spec or cassette option" do
    offenders = files.flat_map do |path|
      File.read(path).scan(assignment).flatten.reject { |v| v == "nil" }
        .map { |v| "#{rel[path]}: #{v}" }
    end
    expect(offenders).to eq []
  end
end
