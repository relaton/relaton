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

      context "when provided index in old format" do
        let(:index) { [{ id: "ISO 1", file: "file1" }, { id: "ISO 2", file: "file2" }] }

        context "without block" do
          context "when pubid provided" do
            it "returns related index row" do
              expect(subject.search(id1)).to eq [{ id: "ISO 1", file: "file1" }]
            end
          end

          context "when string provided" do
            it "returns related index row" do
              expect(subject.search("ISO 2")).to eq [{ id: "ISO 2", file: "file2" }]
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
        expect(File).to receive(:write).with(/index\.yaml$/, subject.index.to_yaml, encoding: "UTF-8")
        subject.save
      end

      it "save empty index" do
        expect(File).to receive(:write).with(/index\.yaml$/, [].to_yaml, encoding: "UTF-8")
        subject.save
      end
    end

    it "#remove_file" do
      expect(File).to receive(:exist?).with(/index\.yaml/).and_return true
      expect(File).to receive(:delete).with(/index\.yaml$/)
      subject.remove_file
    end

    it "#remove_all" do
      subject.remove_all
      index = subject.instance_variable_get(:@index)
      expect(index).to eq []
    end
  end
end
