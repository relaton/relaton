require "open3"

# Regression: lutaml-model deprecates attribute-level `raw: true`
# (`attribute :x, :string, raw: true`) in favour of the mapping-level
# `map_element ..., raw: :content`. Loading the bib models must not print the
# `[DEPRECATED] ... raw: true` warning to stderr. The warning fires once at
# class-definition time, so we load the models in a fresh subprocess.
describe "bib model raw:true deprecation" do
  it "loads bib models without lutaml-model raw:true deprecation warnings" do
    root = File.expand_path("../..", Dir.pwd) # spec/bib -> repo root
    _out, err, status = Open3.capture3(
      RbConfig.ruby, "-Ilib", "-e", 'require "relaton/bib"', chdir: root
    )
    expect(status).to be_success, err
    expect(err).not_to match(/\[DEPRECATED\].*raw: true/)
  end

  it "round-trips a formattedAddress preserving raw content" do
    xml = <<~XML
      <address>
        <formattedAddress>1 Main St&#10;Anytown</formattedAddress>
      </address>
    XML
    addr = Relaton::Bib::Address.from_xml(xml)
    expect(addr.formatted_address).to include("1 Main St")
    expect(addr.to_xml).to match(%r{<formattedAddress>.*1 Main St.*</formattedAddress>}m)
  end

  # Abstract < LocalizedMarkedUpString captures the whole mixed markup content
  # via `map_all to: :content`; the raw markup must survive a round-trip.
  it "round-trips LocalizedMarkedUpString markup content (via Abstract)" do
    xml = %(<abstract format="text/html">a <em>b</em> c<sub>2</sub></abstract>)
    abs = Relaton::Bib::Abstract.from_xml(xml)
    expect(abs.content).to include("<em>b</em>")
    expect(abs.content).to include("<sub>2</sub>")
    out = abs.to_xml
    expect(out).to include("<em>b</em>")
    expect(out).to include("<sub>2</sub>")
  end
end
