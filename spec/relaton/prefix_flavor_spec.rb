# The umbrella spec_helper requires "relaton/db"; Relaton.prefix_flavor is the
# top-level entry point defined in "relaton" (what real users require).
require "relaton"

RSpec.describe "Relaton.prefix_flavor" do
  it "resolves a single-owner prefix to one flavor, as an Array" do
    expect(Relaton.prefix_flavor("NIST")).to eq [Relaton::Nist]
  end

  it "resolves a secondary prefix owned by the same flavor" do
    expect(Relaton.prefix_flavor("NBS")).to eq [Relaton::Nist]
  end

  it "resolves a conflicting prefix to all owning flavors, in registration order" do
    # SUPPORTED_GEMS lists relaton/iec before relaton/iso, so iec comes first.
    expect(Relaton.prefix_flavor("ISO/IEC")).to eq [Relaton::Iec, Relaton::Iso]
  end

  it "resolves a three-way joint prefix to every co-publisher" do
    expect(Relaton.prefix_flavor("ISO/IEC/IEEE"))
      .to eq [Relaton::Iec, Relaton::Iso, Relaton::Ieee]
  end

  # These prefixes are non-obvious and come straight from pubid's grammar,
  # proving the register is sourced from Pubid::<Flavor>.prefixes rather than
  # hand-coded lists (the relaton-db#103 review point).
  it "resolves a pubid-sourced non-obvious BSI prefix (DD)" do
    expect(Relaton.prefix_flavor("DD")).to eq [Relaton::Bsi]
  end

  it "resolves a pubid-sourced IEC series prefix (CISPR)" do
    expect(Relaton.prefix_flavor("CISPR")).to eq [Relaton::Iec]
  end

  it "is case-insensitive" do
    expect(Relaton.prefix_flavor("iso/iec")).to eq Relaton.prefix_flavor("ISO/IEC")
  end

  it "tolerates surrounding whitespace" do
    expect(Relaton.prefix_flavor("  ISO/IEC  ")).to eq Relaton.prefix_flavor("ISO/IEC")
  end

  it "returns [] for an unknown prefix" do
    expect(Relaton.prefix_flavor("BOGUS")).to eq []
  end
end
