require "spec_helper"
require "relaton/w3c/data_fetcher"

RSpec.describe Relaton::W3c::SafeRealize do
  let(:dummy_class) do
    Class.new do
      include Relaton::W3c::SafeRealize
    end
  end

  subject(:handler) { dummy_class.new }

  # A governor whose cooldowns are instant, so throttle paths are exercised
  # without the suite waiting out real minute-scale backoffs.
  let(:governor) do
    Relaton::W3c::Governor.new(base: 0, max: 0, jitter: ->(_) { 0 }, sleeper: ->(_) {})
  end

  before do
    Relaton::W3c::SafeRealize.reset!
    Relaton::W3c::SafeRealize.governor = governor
  end

  after { Relaton::W3c::SafeRealize.reset! }

  describe "#resolve_href" do
    it "returns obj.href when present" do
      obj = double(href: "https://example.com/spec")
      expect(handler.send(:resolve_href, obj)).to eq "https://example.com/spec"
    end

    it "falls back to obj.links.self.href" do
      link_self = double(href: "https://example.com/fallback")
      links = double(self: link_self)
      obj = double(href: nil, links: links)
      expect(handler.send(:resolve_href, obj)).to eq "https://example.com/fallback"
    end
  end

  describe "#realize" do
    let(:href) { "https://example.com/spec" }
    let(:realized) { double("realized_object") }
    let(:obj) { double(href: href) }

    context "when obj.realize succeeds" do
      before { allow(obj).to receive(:realize).and_return(realized) }

      it "returns the realized object (caching is w3c_api's job)" do
        # No memoization here — repeat fetches are served by w3c_api's cache.
        expect(handler.realize(obj)).to eq realized
      end
    end

    context "when the href was already skipped" do
      before { Relaton::W3c::SafeRealize.skipped[href] = true }

      it "returns nil without calling obj.realize" do
        expect(obj).not_to receive(:realize)
        expect(handler.realize(obj)).to be_nil
      end
    end

    # Retries now live upstream (w3c_api retries 403 + connection/timeout,
    # lutaml-hal retries 429 + 5xx), so the handler never retries.
    context "when a network error reaches the handler" do
      before { allow(Relaton.logger_pool).to receive(:warn) }

      it "does not retry and does not skip, so a later reference can try again" do
        call_count = 0
        allow(obj).to receive(:realize) do
          call_count += 1
          raise Faraday::ConnectionFailed, "connection failed"
        end

        result = handler.realize(obj)
        expect(result).to be_nil
        expect(call_count).to eq 1
        expect(Relaton::W3c::SafeRealize.skipped.key?(href)).to be false
        expect(Relaton.logger_pool).to have_received(:warn).with(/Failed to realize object/, anything)
      end
    end

    context "when Lutaml::Hal::NotFoundError is raised" do
      before do
        allow(obj).to receive(:realize).and_raise(Lutaml::Hal::NotFoundError)
        allow(Relaton.logger_pool).to receive(:warn)
      end

      it "warns, skips the resource, and returns nil" do
        result = handler.realize(obj)
        expect(result).to be_nil
        expect(Relaton::W3c::SafeRealize.skipped.key?(href)).to be true
        expect(Relaton.logger_pool).to have_received(:warn).with(/Object not found/, anything)
      end
    end

    context "when a definitive upstream error reaches the handler" do
      before { allow(Relaton.logger_pool).to receive(:warn) }

      it "skips an unclassified upstream error without retrying" do
        call_count = 0
        allow(obj).to receive(:realize) do
          call_count += 1
          raise Lutaml::Hal::Error, "Status: 418"
        end

        result = handler.realize(obj)
        expect(result).to be_nil
        expect(call_count).to eq 1
        expect(Relaton::W3c::SafeRealize.skipped.key?(href)).to be true
        expect(Relaton.logger_pool).to have_received(:warn).with(/Skipping .* upstream error/, anything)
      end

      it "skips a 5xx without retrying" do
        call_count = 0
        allow(obj).to receive(:realize) do
          call_count += 1
          raise Lutaml::Hal::ServerError, "500"
        end

        result = handler.realize(obj)
        expect(result).to be_nil
        expect(call_count).to eq 1
        expect(Relaton::W3c::SafeRealize.skipped.key?(href)).to be true
      end
    end

    # Regression for the Aug-2026 relaton-data-w3c crawl, which permanently
    # blacklisted 1,412 rate-limited resources over four hours because a 429
    # was rescued as a definitive upstream error. A throttle is not a broken
    # resource — see Relaton::W3c::Governor.
    context "when a 429 reaches the handler" do
      before { allow(Relaton.logger_pool).to receive(:warn) }

      it "never blacklists the href, so the resource stays recoverable" do
        allow(obj).to receive(:realize).and_raise(Lutaml::Hal::TooManyRequestsError, "Status: 429")

        expect(handler.realize(obj)).to be_nil
        expect(Relaton::W3c::SafeRealize.skipped.key?(href)).to be false
      end

      # 403 is how api.w3.org signals rate limiting (w3c_api's faraday-retry
      # layer is built around exactly that), so it must not be blacklisted
      # either — the same bug the 429 handling above exists to prevent.
      # lutaml-hal >= 0.2.5 gives it its own ForbiddenError class.
      it "treats a 403 as a throttle too, not a broken resource" do
        allow(obj).to receive(:realize).and_raise(Lutaml::Hal::ForbiddenError, "Status: 403")

        expect(handler.realize(obj)).to be_nil
        expect(Relaton::W3c::SafeRealize.skipped.key?(href)).to be false
        expect(Relaton::W3c::SafeRealize.throttled.key?(href)).to be true
        expect(obj).to have_received(:realize)
          .exactly(Relaton::W3c::SafeRealize::THROTTLE_ATTEMPTS).times
      end

      it "backs off and retries, returning the object once the limiter releases" do
        call_count = 0
        allow(obj).to receive(:realize) do
          call_count += 1
          raise Lutaml::Hal::TooManyRequestsError, "Status: 429" if call_count < 2

          realized
        end

        expect(handler.realize(obj)).to eq realized
        expect(call_count).to eq 2
        expect(governor.throttle_count).to eq 1
      end

      it "gives up after THROTTLE_ATTEMPTS and records a throttle loss" do
        allow(obj).to receive(:realize).and_raise(Lutaml::Hal::TooManyRequestsError, "Status: 429")

        expect(handler.realize(obj)).to be_nil
        expect(obj).to have_received(:realize)
          .exactly(Relaton::W3c::SafeRealize::THROTTLE_ATTEMPTS).times
        # Tracked separately from `skipped`: this is the dataset-completeness
        # signal DataFetcher's throttle budget checks.
        expect(Relaton::W3c::SafeRealize.throttled.key?(href)).to be true
        expect(Relaton::W3c::SafeRealize.skipped.key?(href)).to be false
        expect(Relaton.logger_pool).to have_received(:warn).with(/Throttled/, anything)
      end

      it "feeds the response's Retry-After to the governor" do
        error = Lutaml::Hal::TooManyRequestsError.new("Status: 429")
        error.define_singleton_method(:response) do
          { status: 429, headers: { "retry-after" => "300" } }
        end
        allow(obj).to receive(:realize).and_raise(error)

        expect(governor).to receive(:throttled!).with(retry_after: 300)
          .at_least(:once).and_return(false)
        handler.realize(obj)
      end

      it "waits on the shared cooldown before each attempt" do
        allow(obj).to receive(:realize).and_raise(Lutaml::Hal::TooManyRequestsError, "Status: 429")

        expect(governor).to receive(:wait)
          .exactly(Relaton::W3c::SafeRealize::THROTTLE_ATTEMPTS).times
        handler.realize(obj)
      end

      it "stops retrying once the governor declares the crawl rate-limited" do
        allow(obj).to receive(:realize).and_raise(Lutaml::Hal::TooManyRequestsError, "Status: 429")
        allow(governor).to receive(:throttled!).and_return(true)

        expect(handler.realize(obj)).to be_nil
        expect(obj).to have_received(:realize).once
      end
    end

    context "when a request succeeds" do
      before { allow(obj).to receive(:realize).and_return(realized) }

      it "tells the governor the limiter has released" do
        expect(governor).to receive(:succeeded!)
        handler.realize(obj)
      end

      # lutaml-hal serves a link from its parent page's `_embedded` payload
      # without any HTTP ("Priority 1: check embedded content first"), and that
      # is the common path — one per specification. Counting those as successes
      # would reset the escalation ladder between every pair of version-history
      # 429s, so the governor could never reach its give-up threshold.
      it "says nothing about the limiter when the object came from embedded data" do
        expect(governor).not_to receive(:succeeded!)
        handler.realize(obj, parent_resource: double("page"))
      end

      it "clears an earlier throttle loss, since the document did make it in" do
        Relaton::W3c::SafeRealize.throttled[href] = true
        handler.realize(obj)
        expect(Relaton::W3c::SafeRealize.throttled.key?(href)).to be false
      end
    end
  end
end
