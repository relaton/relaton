require "relaton/ecma/data_fetcher"

describe Relaton::Ecma::MementoParser do
  let(:hit_mem) do
    Nokogiri::HTML(<<~HTML).at("div")
      <div class="entry-content-wrapper clearfix">
        <div><section><div><p>2025</p></div></section></div>
        <div><section><div><p>January 2025</p></div></section></div>
        <div><section><div><p>
          <a href="https://ecma-international.org/wp-content/uploads/Ecma-memento-2025-public.pdf">Download</a>
        </p></div></section></div>
      </div>
    HTML
  end

  subject { described_class.new(hit: hit_mem) }

  it "#fetch_docidentifier" do
    bib = subject.to_bib_hash
    docid = bib[:docidentifier]
    expect(docid.first).to be_instance_of Relaton::Bib::Docidentifier
    expect(docid.first.type).to eq "ECMA"
    expect(docid.first.content).to eq "ECMA MEM/2025"
  end

  it "#fetch_title" do
    bib = subject.to_bib_hash
    title = bib[:title]
    expect(title.first).to be_instance_of Relaton::Bib::Title
    expect(title.first.content).to eq '"Memento 2025" for year 2025'
    expect(title.first.language).to eq "en"
    expect(title.first.script).to eq "Latn"
  end

  it "#fetch_date" do
    bib = subject.to_bib_hash
    date = bib[:date]
    expect(date).to be_instance_of Array
    expect(date.first).to be_instance_of Relaton::Bib::Date
    expect(date.first.at.to_s).to eq "2025-01"
    expect(date.first.type).to eq "published"
  end

  it "#fetch_source" do
    bib = subject.to_bib_hash
    source = bib[:source]
    expect(source).to be_instance_of Array
    expect(source.size).to eq 1
    expect(source.first).to be_instance_of Relaton::Bib::Uri
    expect(source.first.type).to eq "pdf"
    expect(source.first.content.to_s).to eq "https://ecma-international.org/wp-content/uploads/Ecma-memento-2025-public.pdf"
  end

  it "#fetch_ext" do
    bib = subject.to_bib_hash
    expect(bib[:ext]).to be_instance_of Relaton::Ecma::Ext
    expect(bib[:ext].doctype).to be_instance_of Relaton::Bib::Doctype
    expect(bib[:ext].flavor).to eq "ecma"
  end
end
