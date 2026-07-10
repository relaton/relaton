# frozen_string_literal: true

# The store's public entry point is `Relaton.organization`, defined in the root
# entry file (the shared spec_helper only loads relaton/sdo directly).
require "relaton"
require "base64"

RSpec.describe Relaton::Sdo do
  let(:index_url) { "https://sdo.example/index.yaml" }
  let(:index_yaml) { File.read(File.join(__dir__, "fixtures", "index.yaml")) }

  before do
    Relaton::Sdo.configuration.url = index_url
    stub_request(:get, index_url).to_return(body: index_yaml, status: 200)
  end

  describe "Relaton.organization" do
    it "returns an organization for a known abbreviation" do
      org = Relaton.organization("ISO")
      expect(org).to be_a(Relaton::Sdo::Organization)
      expect(org.abbreviation).to eq("ISO")
    end

    it "is case-insensitive" do
      expect(Relaton.organization("iso").abbreviation).to eq("ISO")
    end

    it "returns nil for an unknown abbreviation" do
      expect(Relaton.organization("NOPE")).to be_nil
    end
  end

  describe "#name" do
    let(:org) { Relaton.organization("ISO") }

    it "returns the default (unlanguaged) name" do
      expect(org.name).to eq("International Organization for Standardization")
    end

    it "returns a translated name" do
      expect(org.name("fr")).to eq("Organisation internationale de normalisation")
    end

    it "returns nil for a missing translation" do
      expect(org.name("de")).to be_nil
    end
  end

  describe "#logo_query" do
    let(:org) { Relaton.organization("ISO") }

    it "returns every logo when unfiltered" do
      expect(org.logo_query.size).to eq(3)
    end

    it "filters by style" do
      expect(org.logo_query(style: "default").size).to eq(2)
    end

    it "filters by format (case-insensitive)" do
      result = org.logo_query(format: "PNG")
      expect(result.map(&:format)).to eq(["png"])
    end

    it "filters by size" do
      expect(org.logo_query(size: "700x300").size).to eq(2)
    end

    it "combines filters" do
      result = org.logo_query(format: "eps", size: "700x300", style: "default")
      expect(result.size).to eq(1)
      expect(result.first.url).to eq("https://sdo.example/iso/default-700x300.eps")
    end

    it "returns an empty array when nothing matches" do
      expect(org.logo_query(format: "tiff")).to eq([])
    end

    it "exposes applicability metadata verbatim" do
      red = org.logo_query(style: "red").first
      expect(red.applicability).to eq("stage>=60; latest layout")
    end
  end

  describe "#logo" do
    let(:org) { Relaton.organization("ISO") }

    it "returns the single match" do
      logo = org.logo(format: "eps", style: "default")
      expect(logo).to be_a(Relaton::Sdo::Logo)
      expect(logo.format).to eq("eps")
    end

    it "returns nil when nothing matches" do
      expect(org.logo(style: "ghost")).to be_nil
    end

    it "raises a clear error on an ambiguous match" do
      expect { org.logo(style: "default") }
        .to raise_error(Relaton::Sdo::Error, /narrow/)
    end
  end

  describe Relaton::Sdo::Logo do
    let(:logo) { Relaton.organization("ISO").logo(style: "red") }

    before do
      stub_request(:get, "https://sdo.example/iso/red-latest.svg")
        .to_return(body: "<svg>hi</svg>", status: 200)
    end

    it "fetches the binary content" do
      expect(logo.content).to eq("<svg>hi</svg>")
    end

    it "renders a base64 data URI with the right mimetype" do
      expect(logo.data_uri)
        .to eq("data:image/svg+xml;base64,#{Base64.strict_encode64('<svg>hi</svg>')}")
    end

    it "raises a clear error (naming the URL) when the fetch fails" do
      stub_request(:get, "https://sdo.example/iso/red-latest.svg").to_return(status: 404)
      expect { logo.content }
        .to raise_error(Relaton::Sdo::Error, %r{red-latest\.svg})
    end

    it "caches content across calls (one HTTP request)" do
      logo.content
      logo.content
      expect(a_request(:get, "https://sdo.example/iso/red-latest.svg"))
        .to have_been_made.once
    end

    it "saves to a derived default filename in the CWD" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          path = logo.save
          expect(path).to eq("red-latest.svg")
          expect(File.binread(path)).to eq("<svg>hi</svg>")
        end
      end
    end

    it "saves to a custom path" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "iso.svg")
        expect(logo.save(target)).to eq(target)
        expect(File.binread(target)).to eq("<svg>hi</svg>")
      end
    end

    it "derives a filename without crashing on an unparseable URL" do
      odd = described_class.new(style: "default", size: "700x300", format: "eps",
                                url: "https://sdo.example/a b.eps")
      expect(odd.send(:default_filename)).to eq("a b.eps")
    end

    it "composes a filename from style/size/format when the URL path has no basename" do
      logo = described_class.new(style: "grey", size: "1400x600", format: "svg",
                                 url: "https://sdo.example/iec/")
      expect(logo.send(:default_filename)).to eq("grey-1400x600.svg")
    end
  end

  describe "non-ASCII index" do
    # Regression: the real relaton-data-sdo index carries non-ASCII org names
    # (IEC French, ISO Russian). WebMock hands the body back as ASCII-8BIT, just
    # like Net::HTTP, so caching it must not transcode-crash.
    it "caches and reads a UTF-8 index delivered as a binary body" do
      utf8_index = <<~YAML
        organizations:
          IEC:
            name:
              - content: International Electrotechnical Commission
              - language: fr
                content: Commission électrotechnique internationale
      YAML
      stub_request(:get, index_url)
        .to_return(body: utf8_index.dup.force_encoding("ASCII-8BIT"), status: 200)

      expect { Relaton.organization("IEC") }.not_to raise_error
      expect(Relaton.organization("IEC").name("fr"))
        .to eq("Commission électrotechnique internationale")
    end
  end

  describe "malformed index" do
    it "degrades to no organizations instead of crashing" do
      stub_request(:get, index_url).to_return(body: "- just\n- a list\n", status: 200)
      expect(Relaton.organization("ISO")).to be_nil
    end
  end

  describe "index caching" do
    it "downloads the index once and reuses the on-disk cache" do
      Relaton.organization("ISO")
      Relaton::Sdo::Store.instance.reset! # drop the in-memory memo
      Relaton.organization("IEC")         # must read the fresh disk cache, not re-download

      expect(a_request(:get, index_url)).to have_been_made.once
    end
  end
end
