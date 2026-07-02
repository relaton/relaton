describe Relaton::Isbn::Parser do
  let (:doc) do
    {
      "publishDates" => ["2008"],
      "recordURL" => "https://openlibrary.org/books/OL21119585M/Introduction_to_the_theory",
      "data" => {
        "title" => "Title",
        "subtitle" => "Subtitle",
        "authors" => [{ "name" => "James Arvo", "url" => "https://openlibrary.org/authors/OL21119585M/James_Arvo" }],
        "publishers" => [{ "name" => "AP Professional" }],
        "publish_places" => [{ "name" => "Boston" }, { "name" => "London" }],
      },
      "details" => { "bib_key" => "ISBN:9780120644810" },
    }
  end

  subject { described_class.new doc }

  it "initialize" do
    expect(subject.instance_variable_get(:@doc)).to be doc
  end

  it "create parser & parse" do
    parser = double "parser"
    expect(parser).to receive(:parse).and_return :bib
    expect(described_class).to receive(:new).with(:doc).and_return parser
    expect(described_class.parse(:doc)).to eq :bib
  end

  context "instance methods" do
    context "#parse" do
      let(:doc) { JSON.parse File.read("fixtures/9780120644810.json", encoding: "utf-8") }
      subject { described_class.new(doc["records"].first.last).parse }
      it { is_expected.to be_instance_of Relaton::Bib::ItemData }
    end

    it "#fetched" do
      expect(subject.send(:fetched)).to eq Date.today.to_s
    end

    it "#title" do
      title = subject.send :title
      expect(title).to be_instance_of Array
      expect(title.size).to eq 2
      expect(title.first).to be_instance_of Relaton::Bib::Title
      expect(title.first.content).to eq "Title"
      expect(title.first.type).to eq "main"
      expect(title.last).to be_instance_of Relaton::Bib::Title
      expect(title.last.content).to eq "Subtitle"
      expect(title.last.type).to eq "subtitle"
    end

    it "#docidentifier" do
      docid = subject.send :docidentifier
      expect(docid).to be_instance_of Array
      expect(docid.size).to eq 1
      expect(docid.first).to be_instance_of Relaton::Bib::Docidentifier
      expect(docid.first.content).to eq "9780120644810"
      expect(docid.first.type).to eq "ISBN"
      expect(docid.first.primary).to be true
    end

    it "#source" do
      source = subject.send :source
      expect(source).to be_instance_of Array
      expect(source.size).to eq 1
      expect(source.first).to be_instance_of Relaton::Bib::Uri
      expect(source.first.content.to_s).to eq "https://openlibrary.org/books/OL21119585M/Introduction_to_the_theory"
      expect(source.first.type).to eq "src"
    end

    it "#contributor" do
      expect(subject).to receive(:create_authors).and_return [:authors]
      expect(subject).to receive(:creaate_publishers).and_return [:publishers]
      expect(subject.send(:contributor)).to eq %i[authors publishers]
    end

    it "#create_authors" do
      authors = subject.send :contributor
      expect(authors).to be_instance_of Array
      expect(authors.size).to eq 2
      expect(authors.first).to be_instance_of Relaton::Bib::Contributor
      expect(authors.first.person).to be_instance_of Relaton::Bib::Person
      expect(authors.first.person.name.completename.content).to eq "James Arvo"
      expect(authors.first.person.uri.first.content.to_s).to eq "https://openlibrary.org/authors/OL21119585M/James_Arvo"
      expect(authors.first.role).to be_instance_of Array
      expect(authors.first.role.first.type).to eq "author"
    end

    it "#date" do
      dates = subject.send :date
      expect(dates).to be_instance_of Array
      expect(dates.size).to eq 1
      expect(dates.first).to be_instance_of Relaton::Bib::Date
      expect(dates.first.type).to eq "published"
      expect(dates.first.at.to_s).to eq "2008"
    end

    it "#place" do
      places = subject.send :place
      expect(places).to be_instance_of Array
      expect(places.size).to eq 2
      expect(places.first).to be_instance_of Relaton::Bib::Place
      expect(places.first.city).to eq "Boston"
      expect(places.last.city).to eq "London"
    end
  end
end
