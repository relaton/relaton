# frozen_string_literal: true

require "spec_helper"

# relaton#621: validity dates were typed :date_time, so plain dates came
# back as full timestamps (2010-10-10 -> 2010-10-10T00:00:00+00:00).
# The item-level date fields already use PlainDate for the same reason.
RSpec.describe "Bib::Validity serialization" do
  it "round-trips plain dates without timestamps" do
    item = Relaton::Bib::Item.from_yaml(<<~YAML)
      ---
      id: V
      title:
      - content: T
      docidentifier:
      - content: V 1
        type: BIPM
        primary: true
      validity:
        begins: '2010-10-10'
        ends: '2011-02-03'
        revision: '2011-03-04'
    YAML
    out = YAML.safe_load(item.to_yaml)
    expect(out["validity"]).to eq(
      "begins" => "2010-10-10",
      "ends" => "2011-02-03",
      "revision" => "2011-03-04",
    )
  end
end
