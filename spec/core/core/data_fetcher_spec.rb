describe Relaton::Core::DataFetcher do
  subject { described_class.new("data", "bibxml") }

  describe "::initialize" do
    it { expect(subject.instance_variable_get(:@output)).to eq "data" }
    it { expect(subject.instance_variable_get(:@format)).to eq "bibxml" }
    it { expect(subject.instance_variable_get(:@ext)).to eq "xml" }
    it { expect(subject.instance_variable_get(:@files)).to be_instance_of Set }
    it { expect(subject.instance_variable_get(:@errors)).to be_instance_of Hash }
  end

  describe "::fetch" do
    it "create data fetcher object and call instance method fetch" do
      expect(FileUtils).to receive(:mkdir_p).with("dir")
      expect(described_class).to receive(:new).with("dir", "xml").and_return subject
      expect(subject).to receive(:fetch).with(:source)
      described_class.fetch :source, output: "dir", format: "xml"
    end
  end

  describe "#fetch" do
    it "raise NotImplementedError" do
      expect { subject.fetch }.to raise_error NotImplementedError
    end
  end

  describe "#gh_issue" do
    before { allow(subject).to receive(:gh_issue_channel).and_return ["repo", "msg"]}

    it "clereate GH issue channel" do
      expect(subject.gh_issue).to be_instance_of Relaton::Logger::Channels::GhIssue
    end
  end

  describe "#gh_issue_channel" do
    it "returns repo from ENV and default title" do
      expect(subject.gh_issue_channel).to eq [ENV["GITHUB_REPOSITORY"], "Error fetching documents"]
    end
  end

  describe "#repot_errors" do
    before { subject.instance_variable_set(:@errors, { "key" => true }) }

    context "when GITHUB_REPOSITORY is set" do
      it "call log_error and create GH issue" do
        gh = double(create_issue: nil)
        subject.instance_variable_set(:@gh_issue, gh)
        expect(subject).to receive(:gh_issue).and_return gh
        expect(subject).to receive(:log_error).with("Failed to fetch key")
        expect(gh).to receive(:create_issue)
        subject.report_errors
      end
    end

    context "when GITHUB_REPOSITORY is not set" do
      it "call log_error without creating GH issue" do
        expect(subject).to receive(:gh_issue).and_return nil
        expect(subject).to receive(:log_error).with("Failed to fetch key")
        subject.report_errors
      end
    end
  end

  describe "#log_error" do
    it "raise NoMatchingPatternError" do
      expect { subject.log_error("msg") }.to raise_error NoMatchingPatternError
    end
  end

  describe "#output_file" do
    it "replaces slashes, spaces, and dots with hyphens" do
      file = subject.output_file("ISO/IEC 123-4 Amd. 2")
      expect(file).to eq("data/iso-iec-123-4-amd-2.xml")
    end

    it "replaces dots with hyphens" do
      expect(subject.output_file("IEEE 802.11")).to eq("data/ieee-802-11.xml")
    end

    it "replaces colons with hyphens" do
      expect(subject.output_file("RFC:9110")).to eq("data/rfc-9110.xml")
    end

    it "replaces parentheses with hyphens" do
      file = subject.output_file("ITU-T G.711 (2023)")
      expect(file).to eq("data/itu-t-g-711-2023.xml")
    end

    it "collapses consecutive special chars into one hyphen" do
      file = subject.output_file("ISO / IEC 27001:2022")
      expect(file).to eq("data/iso-iec-27001-2022.xml")
    end

    it "strips trailing special chars" do
      expect(subject.output_file("ISO 123.")).to eq("data/iso-123.xml")
    end

    it "passes through already clean IDs" do
      expect(subject.output_file("rfc9110")).to eq("data/rfc9110.xml")
    end

    it "uses yaml extension for yaml format" do
      fetcher = described_class.new("data", "yaml")
      expect(fetcher.output_file("ISO 123")).to eq("data/iso-123.yaml")
    end
  end

  describe "#serialize"  do
    it "BibXML serialization" do
      expect(subject).to receive(:to_bibxml).with(:doc)
      subject.serialize(:doc)
    end

    it "YAML serialization" do
      subject.instance_variable_set(:@format, "yaml")
      expect(subject).to receive(:to_yaml).with(:doc)
      subject.serialize(:doc)
    end

    it "XML serialization" do
      subject.instance_variable_set(:@format, "xml")
      expect(subject).to receive(:to_xml).with(:doc)
      subject.serialize(:doc)
    end
  end

  describe "#to_yaml" do
    it "raise NotImplementedError" do
      expect { subject.to_yaml(:doc) }.to raise_error NotImplementedError
    end
  end

  describe "#to_xml" do
    it "raise NotImplementedError" do
      expect { subject.to_xml(:doc) }.to raise_error NotImplementedError
    end
  end

  describe "#to_bibxml" do
    it "raise NotImplementedError" do
      expect { subject.to_bibxml(:doc) }.to raise_error NotImplementedError
    end
  end
end
