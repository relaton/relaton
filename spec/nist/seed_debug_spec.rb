require "spec_helper"
require "relaton"
require "relaton/nist"
require "tempfile"
require "zip"

describe "nist seed debug" do
  it "shows what from_ga resolves to" do
    yaml = Zip::File.open("fixtures/index-v2.zip") { |z| z.first.get_input_stream.read }
    f = Tempfile.new(["idx", ".yaml"]); f.write(yaml); f.close
    probe = Relaton::Index::Type.new(:nist, file: f.path, pubid_class: ::Pubid::Nist::Identifier)
    probe.raw_index
    r = Pubid::Nist.parse("NIST IR 8200")
    puts "PROBE search hits: #{probe.search(r).size}"

    seeded = Relaton::Index.find_or_create(:nist, pages_url: "https://relaton.github.io/relaton-data-nist/",
                                           pubid_class: ::Pubid::Nist::Identifier)
    puts "SEEDED class: #{seeded.class}"
    puts "SEEDED source: #{seeded.instance_variable_get(:@source).class rescue 'none'}"
    puts "SEEDED file: #{seeded.instance_variable_get(:@file_io)&.instance_variable_get(:@path) rescue 'n/a'}"
    puts "SEEDED search hits: #{seeded.search(r).size}"
    expect(true).to be true
  end
end
