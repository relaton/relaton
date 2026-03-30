require "relaton/calconnect/data_fetcher"

RSpec.describe Relaton::Calconnect::DataFetcher do
  context "instance methods" do
    subject { described_class.new "data", "yaml" }
    let(:files) { subject.instance_variable_get :@files }

    it "#etagfile" do
      expect(subject.etagfile).to eq "data/etag.txt"
    end

    it "#index" do
      expect(subject.index).to be_instance_of Relaton::Index::Type
    end

    it "#fetch" do
      expect(subject).to receive(:etag).and_return nil
      faraday = double "Faraday instance"
      body = File.read "spec/fixtures/data.yaml", encoding: "UTF-8"
      response = double "Faraday response", status: 200, body: body
      expect(response).to receive(:[]).with(:etag).and_return "1234"
      expect(faraday).to receive(:get).with(no_args).and_return response
      expect(Faraday).to receive(:new)
        .with(Relaton::Calconnect::DataFetcher::ENDPOINT, headers: { "If-None-Match" => nil })
        .and_return faraday
      expect(subject).to receive(:parse_page).with(kind_of(Hash)).and_return(true).exactly(3).times
      expect(subject).to receive(:etag=).with("1234")
      expect(subject.index).to receive(:save)
      expect(subject).to receive(:report_errors)
      subject.fetch
    end

    context "#parse_page" do
      it do
        expect_any_instance_of(Relaton::Calconnect::Scraper).to receive(:parse_page).with(kind_of(Hash)).and_return :bib
        expect(subject).to receive(:write_doc).with("1234", :bib)
        expect(subject.send(:parse_page, { "docid" => [{ "id" => "1234" }] })).to be true
      end

      it "log error" do
        expect_any_instance_of(Relaton::Calconnect::Scraper).to receive(:parse_page).and_raise StandardError
        doc = { "docid" => [{ "id" => "1234" }] }
        expect { subject.send(:parse_page, doc) }.to output(/Document: 1234/).to_stderr_from_any_process
      end
    end

    context "#write_doc" do
      let(:bib) { instance_double Relaton::Calconnect::ItemData }

      before do
        expect(subject).to receive(:serialize).with(bib).and_return :yaml
        expect(subject.index).to receive(:add_or_update).with("1234", "data/1234.yaml")
        expect(File).to receive(:write).with("data/1234.yaml", :yaml, encoding: "UTF-8")
      end

      it do
        subject.send(:write_doc, "1234", bib)
        expect(files).to include "data/1234.yaml"
      end

      it "warn if file exist" do
        files << "data/1234.yaml"
        expect { subject.send(:write_doc, "1234", bib) }.to output(/exist/).to_stderr_from_any_process
      end
    end

    context "serialize" do
      let(:bib) { Relaton::Calconnect::ItemData.new(docnumber: "CC/DIR 10005:2019") }

      it "#to_yaml" do
        expect(subject.send(:to_yaml, bib)).to include "docnumber: CC/DIR 10005:2019"
      end

      context "xml" do
        before { subject.instance_variable_set :@ext, "xml" }

        it "#to_xml" do
          subject.instance_variable_set :@format, "xml"
          expect(subject.send(:to_xml, bib)).to include "<bibdata"
        end

        it "#to_bibxml" do
          subject.instance_variable_set :@format, "bibxml"
          expect(subject.send(:to_bibxml, bib)).to include 'anchor="CC/DIR 10005:2019"'
        end
      end
    end

    context "#etag" do
      it "file exist" do
        expect(File).to receive(:exist?).with("data/etag.txt").and_return true
        expect(File).to receive(:read).with("data/etag.txt", encoding: "UTF-8").and_return "1234"
        expect(subject.send(:etag)).to eq "1234"
      end

      it "file doesn't exist" do
        expect(File).to receive(:exist?).with("data/etag.txt").and_return false
        expect(subject.send(:etag)).to be_nil
      end
    end

    it "#etag=" do
      expect(File).to receive(:write).with("data/etag.txt", "1234", encoding: "UTF-8")
      subject.send(:etag=, "1234")
    end

    it "#report_errors" do
      errors = subject.instance_variable_get(:@errors)
      errors[:title] = false
      errors[:date] = true
      expect(subject).to receive(:report_errors)
      subject.report_errors
    end
  end
end
