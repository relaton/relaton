describe Relaton::Ecma::Bibliography do
  describe ".get" do
    context "unsuccessful" do
      let(:agent) { instance_double Mechanize }
      before do
        allow(Mechanize).to receive(:new).and_return agent
        allow(described_class).to receive(:search).with("ECMA-6").and_return [
          { id: Pubid::Ecma::Identifier.parse("ECMA-6 ed3"), file: "ECMA-6.yaml" }
        ]
      end

      it "raise HTTP Request Timeout error" do
        expect(agent).to receive(:get).and_raise Timeout::Error
        expect do
          described_class.get "ECMA-6"
        end.to raise_error Relaton::RequestError
      end

      it "raise HTTP Not Found error" do
        expect(agent).to receive(:get).and_raise Mechanize::ResponseCodeError.new(double(code: 404), "404")
        expect do
          expect(described_class.get("ECMA-6")).to be_nil
        end.to output(/\[relaton-ecma\] INFO: \(ECMA-6\) Not found\./).to_stderr_from_any_process
      end
    end
  end

  context "search" do
    it "return empty array" do
      expect(described_class).to receive(:parse_ref).with("ECMA-6").and_return nil
      expect(described_class.search("ECMA-6")).to eq []
    end
  end

  # Every example below searches the offline index seeded by
  # spec/ecma/support/webmock.rb — the whole published index, pubid-keyed.
  def match(ref)
    described_class.send(:best_match, ref)&.fetch(:file)
  end

  context "index narrowing" do
    let(:index) { described_class.index }

    it "deserializes the rows into pubid identifiers" do
      expect(index.index).to all include(id: an_instance_of(Pubid::Ecma::Identifiers::Standard))
        .or include(id: an_instance_of(Pubid::Ecma::Identifiers::TechnicalReport))
        .or include(id: an_instance_of(Pubid::Ecma::Identifiers::Memento))
    end

    it "binary-searches by number instead of scanning the whole index" do
      pubid = Pubid::Ecma::Identifier.parse "ECMA-269"
      candidates = index.send(:candidates_by_number, pubid)
      expect(index.index.size).to be > 700
      expect(candidates.map { |r| r[:id].number }.uniq).to eq ["269"]
      expect(candidates.size).to be < 20
    end
  end

  context "row selection" do
    it "returns the latest edition for a bare reference" do
      # ECMA-269 is published as editions 1..9, edition 3 in four volumes.
      expect(match("ECMA-269")).to eq "data/ecma-269-9.yaml"
    end

    it "does not order editions as text" do
      # "9" beats "17" lexicographically; the segment-wise integer key must not.
      expect(match("ECMA-262")).to eq "data/ecma-262-17.yaml"
      expect(match("ECMA-262")).not_to eq "data/ecma-262-9.yaml"
    end

    it "orders editions segment-wise as integers" do
      # `max_by` compares the keys with `<=>`, which Array defines and `>` does
      # not. A text compare gets both of the first two backwards.
      key = ->(ed) { described_class.send(:edition_key, ed) }
      expect(key.call("17") <=> key.call("9")).to eq 1
      expect(key.call("5.1") <=> key.call("5")).to eq 1
      expect(key.call(nil) <=> key.call("1")).to eq(-1)
    end

    it "keeps a dotted edition and its own integer as separate documents" do
      # ECMA-262 ed5.1 is the ONLY dotted edition in the published corpus, so
      # this pair is the only place the dotted ordering is observable end to
      # end. (Neither is the latest edition, so `edition_key` above is what
      # covers the ordering itself.)
      expect(match("ECMA-262 ed5")).to eq "data/ecma-262-5.yaml"
      expect(match("ECMA-262 ed5.1")).to eq "data/ecma-262-5-1.yaml"
    end

    it "honours an edition the reference asks for" do
      expect(match("ECMA-262 ed5.1")).to eq "data/ecma-262-5-1.yaml"
      expect(match("ECMA-269 ed4")).to eq "data/ecma-269-4.yaml"
    end

    it "returns the lowest volume when only the edition is given" do
      expect(match("ECMA-269 ed3")).to eq "data/ecma-269-3-1.yaml"
    end

    it "keeps the four ECMA-269 edition-3 volumes distinct" do
      expect(match("ECMA-269 ed3 vol1")).to eq "data/ecma-269-3-1.yaml"
      expect(match("ECMA-269 ed3 vol2")).to eq "data/ecma-269-3-2.yaml"
      expect(match("ECMA-269 ed3 vol3")).to eq "data/ecma-269-3-3.yaml"
      expect(match("ECMA-269 ed3 vol4")).to eq "data/ecma-269-3-4.yaml"
    end

    it "accepts the space form, which pubid normalizes" do
      expect(match("ECMA 269")).to eq match("ECMA-269")
    end

    it "discriminates a technical report from a standard of the same number" do
      expect(match("ECMA-100")).not_to eq match("ECMA TR/100")
      expect(match("ECMA TR/100")).to eq "data/ecma-tr-100-1.yaml"
    end

    it "finds a memento" do
      expect(match("ECMA MEM/2021")).to eq "data/ecma-mem-2021.yaml"
    end

    it "treats the part as never ignorable" do
      # The old prefix regex let a bare ECMA-418 match the part rows.
      expect(match("ECMA-418-1")).to eq "data/ecma-418-1-2.yaml"
      expect(match("ECMA-418")).not_to eq "data/ecma-418-1-2.yaml"
    end

    it "matches the number exactly, not as a prefix" do
      # The old regex made ECMA-43 also match ECMA-430..434.
      expect(described_class.search("ECMA-43").map { |r| r[:id].number }.uniq).to eq ["43"]
    end

    it "returns nil for a document not in the index" do
      expect(match("ECMA-9999")).to be_nil
    end

    it "requires the reference to parse whole" do
      # The old regex was unanchored at the end, so trailing text after a valid
      # prefix was ignored and `ECMA-6 (draft)` still resolved to ECMA-6.
      expect(match("ECMA-6")).to eq "data/ecma-6-6.yaml"
      expect { match("ECMA-6 (draft)") }.to raise_error Pubid::Errors::ParseError
      expect { match("ECMA-6:1991") }.to raise_error Pubid::Errors::ParseError
    end

    it "tolerates surrounding whitespace" do
      expect(match(" ECMA-6 ")).to eq "data/ecma-6-6.yaml"
    end

    # An unrecognized reference RAISES -- like ISO, ETSI and 3GPP, relaton lets
    # it propagate so a caller can tell "malformed identifier" from "no such
    # document". relaton-cli rescues Parslet::ParseFailed, which
    # Pubid::Errors::ParseError is.
    it "raises when pubid cannot parse the reference" do
      expect { match("not an identifier") }
        .to raise_error Pubid::Errors::ParseError
    end
  end
end
