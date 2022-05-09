RSpec.describe Relaton::Util do
  it "logs HTML entities" do
    expect do
      Relaton::Util.log("Kolbe &amp; Gr&#246;ger 2003")
    end.to output("Kolbe & Gröger 2003\n").to_stderr
  end
end
