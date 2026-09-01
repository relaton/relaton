# frozen_string_literal: true

RSpec.describe Relaton::ThreeGpp::Bibliography do
  # The winning index row's file path — the whole selection decision in one
  # readable value. `best_match` is private, as in the IALA flavor.
  def match(ref)
    described_class.send(:best_match,
                         ::Pubid::Tgpp::Identifier.parse(ref))&.fetch(:file)
  end

  context "index narrowing" do
    let(:index) { described_class.send(:index) }

    it "deserializes the rows into pubid identifiers" do
      expect(index.index).to all(
        include(id: an_instance_of(::Pubid::Tgpp::Identifiers::TechnicalSpecification)
          .or(an_instance_of(::Pubid::Tgpp::Identifiers::TechnicalReport))),
      )
    end

    it "sorts the index, which is what enables the binary search" do
      expect(index.instance_variable_get(:@file_io).sorted).to be true
    end

    # The point of the migration: 88,464 published rows in 3,767 number
    # buckets. Without `pubid_class:` AND a non-String query, every lookup
    # scans the lot.
    # Row counts are deliberately not asserted: the fixture is cut from the
    # live index (`rake spec:update_index_3gpp`) and every 3GPP release adds
    # rows to these groups, so exact numbers would be churn. What must hold is
    # that the bucket is a strict subset keyed on one number.
    it "binary-searches by number instead of scanning the whole index" do
      pubid = ::Pubid::Tgpp::Identifier.parse "3GPP TS 23.207"
      candidates = index.send(:candidates_by_number, pubid)

      expect(candidates).not_to be_empty
      expect(candidates.size).to be < index.index.size
      expect(candidates.map { |r| r[:id].number }.uniq).to eq ["23.207"]
    end

    it "returns an empty bucket for a number that is not in the index" do
      pubid = ::Pubid::Tgpp::Identifier.parse "3GPP TS 99.999"
      expect(index.send(:candidates_by_number, pubid)).to be_empty
    end
  end

  context "row selection" do
    it "returns the newest version for a bare reference" do
      # 37 rows, REL-4 … REL-19. The old `min_by { r[:id] }` returned
      # REL-10/10.0.0 because "1" < "4" — neither newest nor oldest.
      expect(match("3GPP TS 23.207"))
        .to eq "data/ts-23-207-rel-19-19-0-0.yaml"
    end

    it "compares version segments as integers, not as text" do
      # REL-5 runs 5.0.0 … 5.10.0. As strings "5.9.0" > "5.10.0", so a text
      # comparison would return the older document.
      expect(match("3GPP TS 23.207:REL-5"))
        .to eq "data/ts-23-207-rel-5-5-10-0.yaml"
    end

    it "returns exactly the row a fully qualified reference names" do
      expect(match("3GPP TS 23.207:REL-6/6.6.0"))
        .to eq "data/ts-23-207-rel-6-6-6-0.yaml"
    end

    it "takes the 3GPP publisher prefix as optional" do
      expect(match("TS 23.207")).to eq match("3GPP TS 23.207")
    end

    # `parts` and `suffix` are part of the document code, not qualifiers, so
    # neither may be ignored when the reference omits it.
    it "does not treat parts as an ignorable qualifier" do
      expect(match("3GPP TS 29.198-04-1"))
        .to eq "data/ts-29-198-04-1-rel-9-9-0-0.yaml"
      expect(match("3GPP TS 29.198")).to be_nil
    end

    it "does not treat a suffix as an ignorable qualifier" do
      expect(match("3GPP TR 00.01U")).to eq "data/tr-00-01u-umts-3-2-0.yaml"
      expect(match("3GPP TR 00.01")).to be_nil
    end

    # The document type is the identifier's class, and `exclude` rebuilds
    # through `self.class.new(...)`, so the two can never match each other.
    it "keeps the two document types apart" do
      expect(match("3GPP TS 23.207")).not_to be_nil
      expect(match("3GPP TR 23.207")).to be_nil
    end

    it "reaches a row that carries no release at all" do
      # `TS 29.215/2.0.0` is the only release-less row in the whole corpus.
      row = described_class.send(:index).index
        .find { |r| r[:id].number == "29.215" && r[:id].release.nil? }
      expect(row[:id].to_s).to eq "TS 29.215/2.0.0"
      expect(row[:id].version).to eq "2.0.0"
    end

    it "returns nil for a document that is not in the index" do
      expect(match("3GPP TS 99.999")).to be_nil
    end

    # Known limit, pinned so nobody "fixes" the ordering back. 3GPP keeps
    # revising old releases, so the highest version and the newest publication
    # are different documents in ~8% of groups. TS 04.08's newest published
    # document is REL-98/7.21.0 (2004-01-05); its highest version is
    # REL-99/8.0.0 (2000-06-30), and that is what a version key returns. No
    # key computable from the identifier alone can return the other — index
    # rows carry only {id, file} and Pubid::Tgpp has no date.
    it "returns the highest version, which is not always the newest document" do
      expect(match("3GPP TS 04.08")).to eq "data/ts-04-08-rel-99-8-0-0.yaml"
    end
  end

  context "#search" do
    let(:yaml) do
      <<~YAML
        docidentifier:
        - content: 3GPP TS 23.207:REL-19/19.0.0
          type: 3GPP
          primary: true
        docnumber: TS 23.207:REL-19/19.0.0
        title:
        - content: End-to-end Quality of Service (QoS) concept and architecture
        ext:
          doctype:
            content: TS
          flavor: 3gpp
      YAML
    end

    it "fetches the matched document" do
      stub_request(
        :get, "#{described_class::SOURCE}data/ts-23-207-rel-19-19-0-0.yaml"
      ).to_return(status: 200, body: yaml)

      item = described_class.search "3GPP TS 23.207"
      expect(item).to be_a Relaton::ThreeGpp::ItemData
      expect(item.docidentifier.first.content)
        .to eq "3GPP TS 23.207:REL-19/19.0.0"
      expect(item.fetched).to eq Date.today.to_s
    end

    it "returns nil when the document is unreachable" do
      stub_request(
        :get, "#{described_class::SOURCE}data/ts-23-207-rel-19-19-0-0.yaml"
      ).to_return(status: 404)

      expect(described_class.search("3GPP TS 23.207")).to be_nil
    end

    it "returns nil when nothing matches" do
      expect(described_class.search("3GPP TS 99.999")).to be_nil
    end

    it "raises RequestError on a transport failure" do
      expect(Relaton::Index).to receive(:find_or_create).and_raise(Timeout::Error)
      expect { described_class.get("3GPP TS 23.207") }
        .to raise_error Relaton::RequestError
    end
  end

  context "an unrecognized reference" do
    # Mirrors ISO and ETSI: the parse error propagates so relaton-cli can
    # render "… is not a recognized standards identifier"
    # (gems/relaton-cli/lib/relaton/cli/command.rb:324 and
    # subcommand_collection.rb:134 both rescue this exact class).
    it "raises Parslet::ParseFailed" do
      expect { described_class.search("3GPP 1234") }
        .to raise_error Parslet::ParseFailed
    end

    it "raises for a type token with no number" do
      expect { described_class.search("3GPP TS") }
        .to raise_error Parslet::ParseFailed
    end

    # The parse happens outside the transport rescue, so it must never be
    # relabelled as a network failure — the CLI renders those differently.
    it "does not turn the parse failure into a RequestError" do
      error = begin
        described_class.search("3GPP 1234")
        nil
      rescue StandardError => e
        e
      end

      expect(error).to be_a Parslet::ParseFailed
      expect(error).not_to be_a Relaton::RequestError
    end
  end
end
