require "relaton/3gpp/data_fetcher"

RSpec.describe Relaton::ThreeGpp::DataFetcher do
  it "create output dir and run fetcher" do
    expect(FileUtils).to receive(:mkdir_p).with("dir")
    fetcher = double("fetcher")
    expect(fetcher).to receive(:fetch)
    expect(Relaton::ThreeGpp::DataFetcher)
      .to receive(:new).with("dir", "xml").and_return(fetcher)
    Relaton::ThreeGpp::DataFetcher.fetch "status-smg-3GPP", output: "dir", format: "xml"
  end

  context "instance" do
    let(:format) { "xml" }
    # Shaped as Parser#parse builds it: the docidentifier content carries the
    # "3GPP " token, the docnumber does not (parser.rb #parse_docid / #number).
    let(:bib) do
      Relaton::ThreeGpp::ItemData.new(
        docnumber: "TS 01.01:REL-99/8.0.0",
        docidentifier: [
          Relaton::ThreeGpp::Docidentifier.new(
            type: "3GPP", content: "3GPP TS 01.01:REL-99/8.0.0", primary: true
          ),
        ],
      )
    end

    subject { Relaton::ThreeGpp::DataFetcher.new("dir", format) }

    it "#report_errors" do
      errors = subject.instance_variable_get(:@errors)
      errors[:title] = false
      errors[:date] = true
      expect do
        subject.report_errors
      end.to output(/\[relaton-3gpp\] ERROR: Failed to fetch date/).to_stderr_from_any_process
    end

    context "initialize fetcher" do
      let(:format) { "bibxml" }
      it do
        expect(subject.instance_variable_get(:@ext)).to eq "xml"
        expect(subject.instance_variable_get(:@files)).to be_instance_of(Set)
        expect(subject.instance_variable_get(:@output)).to eq "dir"
        expect(subject.instance_variable_get(:@format)).to eq "bibxml"
        expect(subject).to be_instance_of(Relaton::ThreeGpp::DataFetcher)
      end
    end

    context "fetch data" do
      context "get file" do
        let(:last_modified) { "Mon, 22 Nov 2021 14:39:00 GMT" }

        before do
          allow(subject).to receive(:head_last_modified).and_return(last_modified)
          allow(subject).to receive(:download)
        end

        it "skip if no updates" do
          expect(File).to receive(:exist?).with(Relaton::ThreeGpp::DataFetcher::CURRENT).and_return(true)
          allow(File).to receive(:exist?).and_call_original
          expect(YAML).to receive(:load_file).with(Relaton::ThreeGpp::DataFetcher::CURRENT).and_return(
            { "date" => "2021-11-22T14:39:00+00:00" },
          )
          expect(subject).not_to receive(:download)
          expect(subject.get_file(false)).to be_nil
        end

        it "download first time" do
          expect(File).to receive(:exist?).with(Relaton::ThreeGpp::DataFetcher::CURRENT).and_return(false)
          expect(subject).to receive(:download).with(instance_of(URI::HTTPS), /3gpp\.csv$/)
          expect(subject.get_file(false)).to match(/3gpp\.csv$/)
        end

        it "download update" do
          expect(File).to receive(:exist?).with(Relaton::ThreeGpp::DataFetcher::CURRENT).and_return(true)
          expect(YAML).to receive(:load_file).with(Relaton::ThreeGpp::DataFetcher::CURRENT).and_return(
            { "date" => "2021-11-23T14:39:00+00:00" },
          )
          expect(subject).to receive(:download).with(instance_of(URI::HTTPS), /3gpp\.csv$/)
          expect(subject.get_file(false)).to match(/3gpp\.csv$/)
        end

        it "retry file downloading on timeout" do
          expect(subject).to receive(:download).with(instance_of(URI::HTTPS), /3gpp\.csv$/)
            .and_raise(Net::ReadTimeout).exactly(5).times
          expect do
            subject.get_file false
          end.to raise_error(Net::ReadTimeout)
        end

        it "download if current date is empty" do
          expect(File).to receive(:exist?).with(Relaton::ThreeGpp::DataFetcher::CURRENT).and_return(true)
          current = { "date" => "" }
          expect(YAML).to receive(:load_file).with(Relaton::ThreeGpp::DataFetcher::CURRENT).and_return current
          expect(subject).to receive(:download).with(instance_of(URI::HTTPS), /3gpp\.csv$/)
          expect(subject.get_file(false)).to match(/3gpp\.csv$/)
        end

        it "return nil if no last-modified header" do
          allow(subject).to receive(:head_last_modified).and_return(nil)
          expect(subject).not_to receive(:download)
          expect(subject.get_file(false)).to be_nil
        end
      end

      context "fetch" do
        it "skip if no file name" do
          expect(subject).to receive(:get_file).and_return nil
          expect(File).not_to receive(:exist?)
          subject.fetch true
        end

        context do
          before { expect(subject).to receive(:get_file).and_return "file.csv" }

          it "skip if file doesn't exist" do
            expect(File).to receive(:exist?).with("file.csv").and_return false
            expect(File).not_to receive(:size).with("file.csv")
            subject.fetch true
          end

          context do
            before do
              expect(File).to receive(:exist?).with("file.csv").and_return true
            end

            it "skip if file size is too small" do
              expect(File).to receive(:size).with("file.csv").and_return 1_000_000
              expect(CSV).not_to receive(:open)
              subject.fetch true
            end

            context "successfully" do
              before do
                expect(File).to receive(:size).with("file.csv").and_return 25_000_000
                expect(CSV).to receive(:open)
                  .with("file.csv", "r:bom|utf-8", headers: true, col_sep: ";").and_return [:row]
                expect(Relaton::ThreeGpp::Parser).to receive(:parse).with(:row, subject.instance_variable_get(:@errors)).and_return :doc
                expect(subject).to receive(:save_doc).with(:doc)
                expect(File).to receive(:write).with("current.yaml", anything, encoding: "UTF-8")
                expect(subject.index).to receive(:save)
                expect(subject).to receive(:report_errors)
              end

              it "renewal" do
                expect(FileUtils).to receive(:rm_f).with([])
                expect(subject.index).to receive(:remove_all)
                subject.fetch "status-smg-3GPP-force"
              end

              it "update" do
                expect(FileUtils).not_to receive(:rm_f).with("dir/*")
                expect(subject.index).not_to receive(:remove_all)
                subject.fetch "status-smg-3GPP"
              end
            end
          end
        end
      end
    end

    context "save doc" do
      it "skip" do
        expect(subject).not_to receive(:file_name)
        subject.save_doc nil
      end

      # The index key is the parsed pubid, not a String — that is what makes
      # FileIO#save emit the `_type: pubid:3gpp:*` rows an index-v2 needs.
      # Its `to_s` (no publisher token) reproduces the docnumber this used to
      # store, so the key itself does not move.
      it "write doc" do
        expect(File).to receive(:write)
          .with("dir/ts-01-01-rel-99-8-0-0.xml", /<bibdata.+>3GPP TS 01/m, encoding: "UTF-8")
        expect(subject.index).to receive(:add_or_update) do |id, file|
          expect(id).to be_a ::Pubid::Tgpp::Identifier
          expect(id.to_s).to eq "TS 01.01:REL-99/8.0.0"
          expect(file).to eq "dir/ts-01-01-rel-99-8-0-0.xml"
        end
        subject.save_doc bib
      end

      # A crawl must not abort on one bad id, and the index must not be
      # poisoned with a row Relaton::Index would later reject wholesale.
      it "records an error and still writes the doc when the id is unparseable" do
        bad = Relaton::ThreeGpp::ItemData.new(
          docnumber: "not an identifier",
          docidentifier: [
            Relaton::ThreeGpp::Docidentifier.new(
              type: "3GPP", content: "not an identifier", primary: true
            ),
          ],
        )
        expect(File).to receive(:write)
        expect(subject.index).not_to receive(:add_or_update)
        subject.save_doc bad
        expect(subject.instance_variable_get(:@errors)["not an identifier"])
          .to match(/Unparseable primary id/)
      end

      it "warn when file exists and the doc is not transposed or has addidional cntributor" do
        subject.instance_variable_set(:@files, ["dir/ts-01-01-rel-99-8-0-0.xml"])
        expect(subject).to receive(:merge_duplication).with(bib, "dir/ts-01-01-rel-99-8-0-0.xml").and_return nil
        expect(File).not_to receive(:write)
        expect(subject.index).not_to receive(:add_or_update)
        expect { subject.save_doc bib }
          .to output(/File dir\/ts-01-01-rel-99-8-0-0\.xml already exists/).to_stderr_from_any_process
      end
    end

    context "serialise" do
      it "xml" do
        expect(subject.send(:serialize, bib)).to match(/<bibdata.+>TS 01.01:REL-99\/8.0.0<\/docnumber>/m)
      end

      it "yaml" do
        subject.instance_variable_set(:@format, "yaml")
        expect(subject.send(:serialize, bib)).to match(/docnumber: TS 01\.01:REL-99\/8\.0.0/)
      end

      it "other" do
        subject.instance_variable_set(:@format, "bibxml")
        expect(subject.send(:serialize, bib)).to include '<reference anchor="TS 01.01:REL-99/8.0.0">'
      end
    end

    context "merge duplication" do
      before do
        expect(YAML).to receive(:load_file).with(:file).and_return :hash
        expect(Relaton::ThreeGpp::Item).to receive(:from_hash).with(:hash).and_return :bib2
      end

      it "has changed link" do
        expect(subject).to receive(:update_source?).with(:bib, :bib2).and_return true
        expect(subject).to receive(:transposed_relation).with(:bib, :bib2).and_return [:bib1, :bib2, false]
        expect(subject).to receive(:add_contributor).with(:bib1, :bib2).and_return false
        expect(subject.send(:merge_duplication, :bib, :file)).to eq :bib1
      end

      it "has changed transposed relation" do
        expect(subject).to receive(:update_source?).with(:bib, :bib2).and_return false
        expect(subject).to receive(:transposed_relation).with(:bib, :bib2).and_return [:bib1, :bib2, true]
        expect(subject).to receive(:add_contributor).with(:bib1, :bib2).and_return false
        expect(subject.send(:merge_duplication, :bib, :file)).to eq :bib1
      end

      it "has changed contributor" do
        expect(subject).to receive(:update_source?).with(:bib, :bib2).and_return false
        expect(subject).to receive(:transposed_relation).with(:bib, :bib2).and_return [:bib1, :bib2, false]
        expect(subject).to receive(:add_contributor).with(:bib1, :bib2).and_return true
        expect(subject.send(:merge_duplication, :bib, :file)).to eq :bib1
      end
    end

    context "update source" do
      let(:bib_with_source) { Relaton::ThreeGpp::Item.new source: ["link"] }
      let(:bib_without_source) { Relaton::ThreeGpp::Item.new source: [] }

      it "update original source" do
        expect(subject.send(:update_source?, bib_with_source, bib_without_source)).to be true
        expect(bib_with_source.source.size).to eq 1
      end

      it "update new source" do
        expect(subject.send(:update_source?, bib_without_source, bib_with_source)).to be true
        expect(bib_without_source.source.size).to eq 1
      end

      context "no changes" do
        it "both has source" do
          expect(subject.send(:update_source?, bib_with_source, bib_with_source)).to be false
        end

        it "both empty" do
          expect(subject.send(:update_source?, bib_without_source, bib_without_source)).to be false
        end
      end
    end

    context "transposed relation" do
      it "no dates" do
        bib = double("bib", date: [])
        bib2 = double("bib2", date: [])
        expect(subject.send(:transposed_relation, bib, bib2)).to eq [bib, bib2, false]
      end

      it "new doc has no date" do
        bib = double("bib", date: [])
        bib2 = double("bib2", date: [double("date", on: Date.today)])
        expect(subject.send(:transposed_relation, bib, bib2)).to eq [bib2, bib, true]
      end

      it "existing doc has no date" do
        bib = double("bib", date: [double("date", on: Date.today)])
        bib2 = double("bib2", date: [])
        expect(subject.send(:transposed_relation, bib, bib2)).to eq [bib, bib2, false]
      end

      it "both have dates" do
        bib = double("bib", date: [double("date", on: Date.today)])
        bib2 = double("bib2", date: [double("date", on: Date.today)])
        expect(subject).to receive(:check_transposed_date).with(bib, bib2).and_return [bib, bib2, false]
        expect(subject.transposed_relation(bib, bib2)).to eq [bib, bib2, false]
      end
    end

    context "check transposed date" do
      let(:bib) { Relaton::Bib::ItemData.new(date: [Relaton::Bib::Date.new(at: Date.today.to_s)]) }
      let(:bib2) { Relaton::Bib::ItemData.new(date: [Relaton::Bib::Date.new(at: Date.today.to_s)]) }

      it "new doc is older" do
        bib = Relaton::Bib::ItemData.new(date: [Relaton::Bib::Date.new(at: (Date.today - 1).to_s)])
        expect(subject).to receive(:add_transposed_relation).with(bib, bib2)
        expect(subject.check_transposed_date(bib, bib2)).to eq [bib, bib2, true]
      end

      it "new doc is newer" do
        bib2 = Relaton::Bib::ItemData.new(date: [Relaton::Bib::Date.new(at: (Date.today - 1).to_s)])
        expect(subject).to receive(:add_transposed_relation).with(bib2, bib)
        expect(subject.check_transposed_date(bib, bib2)).to eq [bib2, bib, true]
      end

      it "dates are equal" do
        expect(subject.check_transposed_date(bib, bib2)).to eq [bib, bib2, false]
      end
    end

    it "add transposed relation" do
      bib = Relaton::ThreeGpp::Item.new
      bib2 = Relaton::ThreeGpp::Item.new
      subject.add_transposed_relation(bib, bib2)
      expect(bib.relation.first.bibitem).to eq bib2
    end

    context "add contributor" do
      it "new doc has a different contributor" do
        surname = Relaton::Bib::LocalizedString.new content: "Doe"
        forename = Relaton::Bib::FullNameType::Forename.new content: "John"
        name = Relaton::Bib::FullName.new surname: surname, forename: [forename]
        person = Relaton::Bib::Person.new name: name
        contrib = Relaton::Bib::Contributor.new person: person
        bib = Relaton::ThreeGpp::Item.new contributor: [contrib]

        surname2 = Relaton::Bib::LocalizedString.new content: "Smith"
        forename2 = Relaton::Bib::FullNameType::Forename.new content: "John"
        name2 = Relaton::Bib::FullName.new surname: surname2, forename: [forename2]
        person2 = Relaton::Bib::Person.new name: name2
        contrib2 = Relaton::Bib::Contributor.new person: person2
        bib2 = Relaton::ThreeGpp::Item.new contributor: [contrib2]

        expect(subject.add_contributor(bib, bib2)).to be true
        expect(bib.contributor.size).to eq 2
        expect(bib.contributor[0]).to be contrib
        expect(bib.contributor[1]).to be contrib2
      end

      it "new doc has the same contributor with different affiliation" do
        surname = Relaton::Bib::LocalizedString.new content: "Doe"
        forename = Relaton::Bib::FullName::Forename.new content: "John"
        name = Relaton::Bib::FullName.new surname: surname, forename: [forename]
        person = Relaton::Bib::Person.new name: name
        contrib = Relaton::Bib::Contributor.new person: person
        bib = Relaton::ThreeGpp::Item.new contributor: [contrib]

        org_name = Relaton::Bib::TypedLocalizedString.new content: "Org"
        org = Relaton::Bib::Organization.new name: [org_name]
        aff = Relaton::Bib::Affiliation.new organization: org
        surname2 = Relaton::Bib::LocalizedString.new content: "Doe"
        forename2 = Relaton::Bib::FullName::Forename.new content: "John"
        name2 = Relaton::Bib::FullName.new surname: surname2, forename: [forename2]
        person2 = Relaton::Bib::Person.new name: name2, affiliation: [aff]
        contrib2 = Relaton::Bib::Contributor.new person: person2
        bib2 = Relaton::ThreeGpp::Item.new contributor: [contrib2]

        expect(subject.add_contributor(bib, bib2)).to be true
        expect(bib.contributor.size).to eq 1
        expect(bib.contributor[0]).to be contrib
        expect(bib.contributor[0].person.affiliation.size).to eq 1
      end

      it "new doc has the same contributor with the same affiliation" do
        surname = Relaton::Bib::LocalizedString.new content: "Doe"
        forename = Relaton::Bib::FullName::Forename.new content: "John"
        name = Relaton::Bib::FullName.new surname: surname, forename: [forename]
        org_name = Relaton::Bib::TypedLocalizedString.new content: "Org"
        org = Relaton::Bib::Organization.new name: [org_name]
        aff = Relaton::Bib::Affiliation.new organization: org
        person = Relaton::Bib::Person.new name: name, affiliation: [aff]
        contrib = Relaton::Bib::Contributor.new person: person
        bib = Relaton::ThreeGpp::Item.new contributor: [contrib]

        surname2 = Relaton::Bib::LocalizedString.new content: "Doe"
        forename2 = Relaton::Bib::FullName::Forename.new content: "John"
        name2 = Relaton::Bib::FullName.new surname: surname2, forename: [forename2]
        org_name2 = Relaton::Bib::TypedLocalizedString.new content: "Org"
        org2 = Relaton::Bib::Organization.new name: [org_name2]
        aff2 = Relaton::Bib::Affiliation.new organization: org2
        person2 = Relaton::Bib::Person.new name: name2, affiliation: [aff2]
        contrib2 = Relaton::Bib::ContributionInfo.new person: person2
        bib2 = Relaton::ThreeGpp::Item.new contributor: [contrib2]

        expect(subject.add_contributor(bib, bib2)).to be false
        expect(bib.contributor.size).to eq 1
        expect(bib.contributor[0]).to be contrib
        expect(bib.contributor[0].person.affiliation.size).to eq 1
      end

      it "skip organization" do
        org_name = Relaton::Bib::TypedLocalizedString.new content: "Org"
        org = Relaton::Bib::Organization.new name: [org_name]
        contrib = Relaton::Bib::Contributor.new organization: org
        bib = Relaton::ThreeGpp::Item.new contributor: [contrib]

        org2_name = Relaton::Bib::TypedLocalizedString.new content: "Org"
        org2 = Relaton::Bib::Organization.new name: [org2_name]
        contrib2 = Relaton::Bib::Contributor.new organization: org2
        bib2 = Relaton::ThreeGpp::Item.new contributor: [contrib2]

        expect(subject.add_contributor(bib, bib2)).to be false
        expect(bib.contributor.size).to eq 1
        expect(bib.contributor[0]).to be contrib
      end
    end
  end

  # The producer and the consumer must agree on the index shape, and nothing
  # else checks that end to end: a missing `pubid_class:` on the writer emits
  # v1-shaped rows under a v2 name with no error, and the reader then rejects
  # the whole index. Write through the fetcher's own index config, read it back
  # through a fresh Type, and require every row to survive.
  context "the index it writes is one the consumer can read" do
    # `FileIO#save` writes the `file:` path verbatim (FileStorage#write does no
    # storage_dir join), so a producer index saves relative to the CWD — which
    # is how the real crawler works, inside the data repo's checkout. Run the
    # example from a temp dir so it cannot drop an index into spec/3gpp/.
    around do |example|
      Dir.mktmpdir("relaton-3gpp-roundtrip") do |dir|
        @dir = dir
        Dir.chdir(dir) { example.run }
      ensure
        Relaton::Index.pool.remove "3gpp"
      end
    end

    let(:ids) do
      ["TS 23.207:REL-19/19.0.0", "TS 29.198-04-1:REL-5/5.0.0",
       "TR 00.01U:UMTS/3.0.0", "TS 29.215/2.0.0"]
    end

    it "round-trips every id through the pubid hash form" do
      producer = Relaton::Index.find_or_create(
        "3gpp", file: "#{Relaton::ThreeGpp::INDEXFILE}.yaml",
        pubid_class: ::Pubid::Tgpp::Identifier
      )
      producer.remove_all
      ids.each do |id|
        docid = Relaton::ThreeGpp::Docidentifier.new(
          type: "3GPP", content: "3GPP #{id}", primary: true
        )
        producer.add_or_update docid.pubid, "data/#{id.gsub(/\W+/, '-').downcase}.yaml"
      end
      producer.save

      path = File.join(@dir, "#{Relaton::ThreeGpp::INDEXFILE}.yaml")
      # The `_type:` tag is what makes the row a pubid row rather than a v1
      # string; without `pubid_class:` on the writer it would be absent.
      expect(File.read(path)).to include "_type: pubid:3gpp:technical-report"

      consumer = Relaton::Index::Type.new(
        "3GPP", nil, path, nil, ::Pubid::Tgpp::Identifier
      )
      expect(consumer.index.map { |r| r[:id].to_s }).to match_array ids
      # Sorted by root.number on load, which is what keeps the bsearch valid.
      expect(consumer.instance_variable_get(:@file_io).sorted).to be true
    end
  end
end
