describe Relaton::Index::Type do
  before { Relaton::Index.instance_variable_set(:@config, nil) }

  context "instace methods" do
    subject { described_class.new(:ISO, :url, "index.yaml") }

    context "#actual?" do
      it "no url and file" do
        expect(subject.actual?).to be true
      end

      it "new url" do
        expect(subject.instance_variable_get(:@file_io)).to receive(:url).and_return :old
        expect(subject.actual?(url: :new)).to be false
      end

      it "new file" do
        expect(subject.actual?(file: :new)).to be false
      end

      it "same url and file" do
        expect(subject.actual?(url: :url, file: "index.yaml")).to be true
      end
    end

    context "#add_or_update" do
      let(:id) { TestIdentifier.create(number: 1, publisher: "ISO") }

      it "add" do
        subject.add_or_update id, "file2"
        expect(subject.index).to eq [{ id: id, file: "file2" }]
      end

      it "update" do
        subject.add_or_update id, "file2"
        expect(subject.index).to eq [{ id: id, file: "file2" }]
        subject.add_or_update id, "file3"
        expect(subject.index).to eq [{ id: id, file: "file3" }]
      end
    end

    context "#search" do
      let(:id1) { TestIdentifier.create(number: 1, publisher: "ISO") }
      let(:id2) { TestIdentifier.create(number: 2, publisher: "ISO") }

      before do
        subject.add_or_update id1, "file1"
        subject.add_or_update id2, "file2"
      end

      context "without block" do
        context "when pubid provided" do
          it "returns related index row" do
            expect(subject.search(id1)).to eq [{ id: id1, file: "file1" }]
          end
        end

        context "when string provided" do
          it "returns related index row" do
            expect(subject.search("ISO 2")).to eq [{ id: id2, file: "file2" }]
          end

          context "when string match only partially" do
            it "returns all matching index rows" do
              expect(subject.search("ISO")).to eq [{ id: id1, file: "file1" },
                                                   { id: id2, file: "file2" }]
            end
          end
        end
      end

      context "with block" do
        it "returns entries matching with provided block conditions" do
          expect(subject.search { |i| i[:id] == id1 }).to eq [{ id: id1, file: "file1" }]
        end
      end

      # Without a block the query is the REFERENCE: two identifiers take
      # pubid's asymmetric subset match, so a component the query omits matches
      # any value. A caller that needs exact equality passes a block; CCSDS and
      # IETF are the two that do.
      context "without block, matching identifiers" do
        let(:ed1) { TestIdentifier.create(number: 3, publisher: "ISO", edition: "1") }
        let(:ed2) { TestIdentifier.create(number: 3, publisher: "ISO", edition: "2") }
        let(:bare) { TestIdentifier.create(number: 3, publisher: "ISO") }

        before do
          subject.add_or_update ed1, "file3-1"
          subject.add_or_update ed2, "file3-2"
        end

        it "lets a reference reach the rows that state more" do
          expect(subject.search(bare).map { |r| r[:file] })
            .to eq %w[file3-1 file3-2]
        end

        it "keeps a fully stated reference on its own row" do
          expect(subject.search(ed2)).to eq [{ id: ed2, file: "file3-2" }]
        end

        it "is not symmetric: a stated edition does not match a bare row" do
          subject.add_or_update bare, "file3"
          expect(subject.search(ed1).map { |r| r[:file] }).to eq %w[file3-1]
        end

        it "takes exact equality from a block instead" do
          expect(subject.search(bare) { |r| r[:id] == bare }).to be_empty
        end

        context "with exact: true" do
          it "does not let a reference reach the rows that state more" do
            expect(subject.search(bare, exact: true)).to be_empty
          end

          it "returns the row equal to the reference" do
            subject.add_or_update bare, "file3"
            expect(subject.search(bare, exact: true)).to eq [{ id: bare, file: "file3" }]
          end

          it "compares a String with == instead of a substring" do
            subject.add_or_update "ISO 30", "file30"
            expect(subject.search("ISO 3", exact: true)).to be_empty
            expect(subject.search("ISO 30", exact: true)).to eq [{ id: "ISO 30", file: "file30" }]
          end

          it "refuses a block as well" do
            expect { subject.search(bare, exact: true) { true } }
              .to raise_error ArgumentError, /exact/
          end
        end
      end

      context "when provided index in old format" do
        let(:index) { [{ id: "ISO 1", file: "file1" }, { id: "ISO 2", file: "file2" }] }

        context "without block" do
          context "when pubid provided" do
            it "returns related index row" do
              expect(subject.search(id1)).to eq [{ id: id1, file: "file1" }]
            end
          end

          context "when string provided" do
            it "returns related index row" do
              expect(subject.search("ISO 2")).to eq [{ id: id2, file: "file2" }]
            end
          end
        end
      end
    end

    context "#search with binary search" do
      subject do
        described_class.new(
          :ISO, :url, "index.yaml", nil, TestIdentifier
        )
      end

      let(:id1) { TestIdentifier.create(number: 1, publisher: "ISO") }
      let(:id2) { TestIdentifier.create(number: 2, publisher: "ISO") }
      let(:id3) { TestIdentifier.create(number: 3, publisher: "ISO") }

      context "when index is sorted" do
        before do
          sorted_data = [
            { id: id1, file: "file1" },
            { id: id2, file: "file2" },
            { id: id3, file: "file3" },
          ]
          subject.instance_variable_set(:@index, sorted_data)
          subject.instance_variable_get(:@file_io).sorted = true
        end

        it "finds exact pubid match via binary search" do
          expect(subject.search(id2)).to eq [
            { id: id2, file: "file2" },
          ]
        end

        it "returns empty when pubid not found" do
          id4 = TestIdentifier.create(number: 4, publisher: "ISO")
          expect(subject.search(id4)).to eq []
        end

        it "narrows candidates for block search" do
          yielded = []
          subject.search(id2) do |i|
            yielded << i
            true
          end
          expect(yielded).to eq [{ id: id2, file: "file2" }]
        end

        it "falls back to full scan for string search" do
          result = subject.search("ISO 2")
          expect(result).to eq [{ id: id2, file: "file2" }]
        end
      end

      # The narrowing key is the base *document's* number (`id.root.number`),
      # not the id's own number. A supplement/amendment/corrigendum (own number
      # differs from its origin) must cluster with — and be reachable from — its
      # base document. If the key used the id's own number, `supp` below would
      # sort under "2" and fall outside the "9001" candidate window.
      context "with a supplement whose root document differs from its own number" do
        let(:doc)  { TestIdentifier.create(number: 9001, publisher: "ISO") }
        let(:supp) { TestIdentifier.create(number: 2, publisher: "ISO").tap { |s| s.root = doc } }
        let(:other) { TestIdentifier.create(number: 9002, publisher: "ISO") }

        before do
          # Sorted by root.number.to_s: doc/supp -> "9001", other -> "9002".
          subject.instance_variable_set(:@index, [
                                          { id: doc, file: "doc" },
                                          { id: supp, file: "supp" },
                                          { id: other, file: "other" },
                                        ])
          subject.instance_variable_get(:@file_io).sorted = true
        end

        it "narrows a search for the document to include the supplement, not the other document" do
          yielded = []
          subject.search(doc) do |i|
            yielded << i
            false
          end
          expect(yielded).to contain_exactly({ id: doc, file: "doc" },
                                             { id: supp, file: "supp" })
        end
      end

      context "when index is unsorted" do
        before do
          unsorted_data = [
            { id: id3, file: "file3" },
            { id: id1, file: "file1" },
            { id: id2, file: "file2" },
          ]
          subject.instance_variable_set(:@index, unsorted_data)
          subject.instance_variable_get(:@file_io).sorted = false
        end

        it "falls back to full scan for pubid search" do
          expect(subject.search(id1)).to eq [
            { id: id1, file: "file1" },
          ]
        end
      end
    end

    context "#save" do
      it "save index" do
        expect(File).to receive(:binwrite).with(/index\.yaml$/, subject.index.to_yaml)
        subject.save
      end

      it "save empty index" do
        expect(File).to receive(:binwrite).with(/index\.yaml$/, [].to_yaml)
        subject.save
      end
    end

    it "#remove_file" do
      expect(File).to receive(:exist?).with(/index\.yaml/).and_return true
      expect(File).to receive(:delete).with(/index\.yaml$/)
      subject.remove_file
    end

    # A processor's #remove_index_file needs no `pubid_class:`. The delete
    # resolves the path from `url` and `file` only, and never reads the index.
    context "#remove_file with url: true" do
      let(:dir) { Dir.mktmpdir }
      let(:cached) { File.join(dir, ".relaton", "iso", "index.yaml") }

      # A `before`, not an `around`: the outer `before` resets the config,
      # and an `around` runs ahead of it.
      before do
        Relaton::Index.configure { |c| c.storage_dir = dir }
        FileUtils.mkdir_p File.dirname(cached)
        File.write cached, "--- []\n"
      end

      after { FileUtils.rm_rf dir }

      it "removes the cached file without a pubid_class" do
        described_class.new(:ISO, true, "index.yaml").remove_file
        expect(File.exist?(cached)).to be false
      end

      it "removes the same file with a pubid_class, and never calls it" do
        pubid_class = double("pubid_class") # raises on any message
        described_class.new(:ISO, true, "index.yaml", nil, pubid_class)
          .remove_file
        expect(File.exist?(cached)).to be false
      end
    end

    it "#remove_all" do
      subject.remove_all
      index = subject.instance_variable_get(:@index)
      expect(index).to eq []
    end
  end
end
