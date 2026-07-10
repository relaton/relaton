require "open3"

# Regression: the IEC ext `tc-sc-officers-note` moved from attribute-level
# `raw: true` to mapping-level `map_element ..., raw: :content`. Loading the
# model must not emit lutaml-model's deprecation warning, and the raw markup
# inside the note must still round-trip unchanged.
describe "iec ext raw:true deprecation" do
  it "loads iec models without lutaml-model raw:true deprecation warnings" do
    root = File.expand_path("../..", Dir.pwd) # spec/iec -> repo root
    _out, err, status = Open3.capture3(
      RbConfig.ruby, "-Ilib", "-e", 'require "relaton/iec"', chdir: root
    )
    expect(status).to be_success, err
    expect(err).not_to match(/\[DEPRECATED\].*raw: true/)
  end

  it "round-trips tc-sc-officers-note preserving raw markup" do
    xml = %(<ext><tc-sc-officers-note>) +
          %(<p id="p1">note <em>markup</em></p></tc-sc-officers-note></ext>)
    ext = Relaton::Iec::Ext.from_xml(xml)
    expect(ext.tc_sc_officers_note).to include(%(<p id="p1">note <em>markup</em></p>))
    expect(Relaton::Iec::Ext.to_xml(ext)).to include("<em>markup</em>")
  end
end
