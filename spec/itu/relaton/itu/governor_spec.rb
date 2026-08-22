require "relaton/itu/governor"

# ITU's binding of Relaton::Core::Governor. The ladder is core's and is specced
# there; what is tested here is the one thing only this flavor knows — which
# failures mean "the F5 WAF is throttling us" and which mean "that document is
# not there".
RSpec.describe Relaton::Itu::Governor do
  # A Mechanize::ResponseCodeError carrying `code`, without a live page.
  def response_error(code)
    instance_double(Mechanize::ResponseCodeError, response_code: code).tap do |e|
      allow(e).to receive(:is_a?) { |k| k == Mechanize::ResponseCodeError }
    end
  end

  it "uses ITU's own env prefix" do
    expect(described_class.new.env_prefix).to eq "RELATON_ITU"
  end

  describe ".throttle?" do
    it "treats a 503 as a rate limit — what /rec answers when pushed" do
      expect(described_class.throttle?(response_error("503"))).to be true
    end

    it "treats a gateway failure as a rate limit" do
      %w[429 502 504].each do |code|
        expect(described_class.throttle?(response_error(code))).to be true
      end
    end

    it "does NOT treat a 404 as a rate limit" do
      # The one that matters: a genuinely missing document must cost that
      # document, never a pool-wide cooldown for every other worker.
      expect(described_class.throttle?(response_error("404"))).to be false
    end

    it "does NOT treat a per-resource 500 as a rate limit" do
      # Same call the W3C governor makes: a persistent 5xx on one resource is a
      # broken record, and routing it here would open a cooldown per bad page.
      expect(described_class.throttle?(response_error("500"))).to be false
    end

    it "treats the /pub soft block as a rate limit" do
      # A 302 to notfound.aspx, which Mechanize follows to a perfectly good 200
      # — indistinguishable from "no such document" unless it is marked.
      soft = Class.new(StandardError) { include Relaton::Itu::Governor::SoftBlock }
      expect(described_class.throttle?(soft.new)).to be true
    end

    it "ignores a transport error, which is not a rate limit" do
      expect(described_class.throttle?(Errno::ECONNRESET.new)).to be false
    end
  end
end
