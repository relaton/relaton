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

    context "with a pathologically long docid" do
      # A 313-char amendment docnumber (pubid embeds the full
      # "(Amendment to … as amended by …)" clause) would otherwise produce a
      # >255-byte basename and make File.write raise Errno::ENAMETOOLONG.
      let(:long_id) { "IEEE Std 802.3bs-2017 (Amendment to IEEE Std 802.3-2015 as amended by " + (["IEEE Std 802.3bw-2015"] * 10).join(", ") + ")" }

      it "caps the basename at or below the OS 255-byte limit" do
        expect(long_id.bytesize).to be > 255
        expect(File.basename(subject.output_file(long_id)).bytesize).to be <= 255
      end

      it "is deterministic for the same docid" do
        expect(subject.output_file(long_id)).to eq(subject.output_file(long_id))
      end

      it "produces distinct filenames for distinct long docids" do
        expect(subject.output_file("#{long_id} A")).not_to eq(subject.output_file("#{long_id} B"))
      end

      it "keeps a readable prefix and appends a short digest" do
        base = File.basename(subject.output_file(long_id), ".xml")
        expect(base).to start_with("ieee-std-802-3bs-2017")
        expect(base).to match(/-[0-9a-f]{12}\z/)
      end

      it "stays valid UTF-8 even when truncation splits a multibyte char" do
        multibyte = "café-" + ("é" * 300)
        base = File.basename(subject.output_file(multibyte))
        expect(base.bytesize).to be <= 255
        expect(base).to be_valid_encoding
      end
    end
  end

  describe "#unique_output_file" do
    # `output_file` collapses ".", ",", "/", ":", "(", ")", "-" and whitespace
    # all to "-", so distinct docids can map to one path. Live instance:
    # relaton-data-iana's `rpki/signed-objects` vs `rpki-signed-objects`.
    let(:a) { "rpki/signed-objects" }
    let(:b) { "rpki-signed-objects" }

    it "collapses two distinct docids onto one path (the bug)" do
      expect(subject.output_file(a)).to eq subject.output_file(b)
    end

    it "returns the plain path when it is free" do
      expect(subject.unique_output_file(a)).to eq subject.output_file(a)
    end

    it "gives a second, different docid a path of its own" do
      first = subject.unique_output_file(a)
      second = subject.unique_output_file(b)
      expect(second).not_to eq first
      expect(File.dirname(second)).to eq "data"
      expect(File.extname(second)).to eq ".xml"
    end

    it "is a no-op for the SAME docid seen twice" do
      # A genuine duplicate must keep resolving to one path, so each flavor's
      # own duplicate handling (skip / merge / last-wins) still fires.
      expect(subject.unique_output_file(a)).to eq subject.unique_output_file(a)
    end

    it "is deterministic across fetcher instances" do
      other = described_class.new("data", "bibxml")
      other.unique_output_file(a)
      expect(other.unique_output_file(b)).to eq(
        begin
          subject.unique_output_file(a)
          subject.unique_output_file(b)
        end,
      )
    end

    it "keys the suffix on the docid, not on encounter order" do
      # Adding a registry must not renumber an existing file: b's
      # disambiguated name is the same whatever else was fetched first.
      subject.unique_output_file(a)
      mine = subject.unique_output_file(b)

      other = described_class.new("data", "bibxml")
      other.unique_output_file("something/else")
      other.unique_output_file(a)
      expect(other.unique_output_file(b)).to eq mine
    end

    it "keeps one file per document whatever the call order" do
      # The invariant the whole method exists for: distinct docids never share a
      # path, the same docid always gets the same path, and asking again is
      # idempotent. Exercised over several orders and a three-way clash.
      [[a, b], [b, a], [a, a, b], ["x/y", "x-y", "x.y"],
       ["x/y", "x-y", "x.y", "x-y", "x/y"]].each do |sequence|
        fetcher = described_class.new("data", "bibxml")
        paths = sequence.to_h { |docid| [docid, fetcher.unique_output_file(docid)] }
        expect(paths.values.uniq.size).to eq(sequence.uniq.size), "order #{sequence.inspect}"
        # idempotent: re-asking returns what it returned the first time
        paths.each { |docid, path| expect(fetcher.unique_output_file(docid)).to eq path }
      end
    end

    it "keeps the disambiguated basename within the byte cap" do
      long = "#{'A' * 300}/x"
      other = "#{'A' * 300}-x"
      subject.unique_output_file(long)
      file = subject.unique_output_file(other)
      expect(File.basename(file).bytesize).to be <= 255
      expect(file).not_to eq subject.output_file(long)
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
