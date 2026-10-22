require "spec_helper"
require "pubid"
require "relaton/index"
require "yaml"
require "tmpdir"
require "fileutils"

# Retrieval half of the shared Ruby/TypeScript conformance suite: the same
# fixture pack (conformance/retrieval/) is executed here and by relaton-ts.
# The pinned contract is index search semantics — Pubid::Identifier#=== over
# the data repos' v2 lean-pubid rows — so a reference resolves to the same
# records whichever stack asks.
describe "retrieval conformance fixture" do
  let(:index_path) { File.expand_path("../../conformance/retrieval/index-v2.yaml", __dir__) }
  cases = YAML.safe_load_file(File.expand_path("../../conformance/retrieval/expectations.yaml", __dir__))["cases"]

  def index
    @index ||= Dir.mktmpdir("retrieval-conformance") do |tmp|
      FileUtils.cp(index_path, "#{tmp}/index-v2.yaml")
      # The index reads the file straight off the process directory;
      # construct and force-load inside so the rows are cached on the type.
      Dir.chdir(tmp) do
        t = Relaton::Index::Type.new(:iso, file: "index-v2.yaml",
                                     pubid_class: Pubid::Iso::Identifier)
        t.raw_index
        t
      end
    end
  end

  def parse(query)
    (query.start_with?("IEC") ? Pubid::Iec : Pubid::Iso).parse(query)
  end

  cases.each do |case_|
    describe case_["name"] do
      it "resolves the expected records" do
        ref = parse(case_["query"])
        matched = if case_["family"]
                    index.family(ref).members.map { |m| m[:file] }.sort
                  else
                    index.search(ref).map { |m| m[:file] }.sort
                  end
        expect(matched).to eq(case_["expect"].sort)
      end
    end
  end
end
