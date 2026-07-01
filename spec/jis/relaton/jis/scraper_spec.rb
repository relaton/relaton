# frozen_string_literal: true

require "relaton/jis/scraper"

describe Relaton::Jis::Scraper do
  context "instance methods" do
    subject { described_class.new "https://document.url" }

    context "#fetch" do
      let(:doc) { Nokogiri::HTML File.read "fixtures/jis_x_0208_1997.html", encoding: "UTF-8" }

      before do
        agent = subject.instance_variable_get :@agent
        expect(agent).to receive(:get)
          .with("https://document.url").and_return doc
      end

      it do
        item = subject.fetch
        expect(item).to be_instance_of Relaton::Jis::ItemData
        expect(item.title.size).to eq 2
        expect(item.title.first).to be_instance_of Relaton::Bib::Title
        expect(item.source.size).to eq 2
        expect(item.source.first).to be_instance_of Relaton::Bib::Uri
        expect(item.abstract.first).to be_instance_of Relaton::Bib::Abstract
        expect(item.docidentifier.first).to be_instance_of Relaton::Jis::Docidentifier
        expect(item.date.size).to eq 2
        expect(item.date.first).to be_instance_of Relaton::Bib::Date
        expect(item.type).to eq "standard"
        expect(item.language.first).to eq "ja"
        expect(item.script.first).to eq "Jpan"
        expect(item.status).to be_instance_of Relaton::Bib::Status
        expect(item.ext).to be_instance_of Relaton::Jis::Ext
        expect(item.ext.doctype).to be_instance_of Relaton::Jis::Doctype
        expect(item.ext.ics.first).to be_instance_of Relaton::Bib::ICS
        expect(item.ext.structuredidentifier).to be_instance_of Relaton::Jis::StructuredIdentifier
        expect(item.contributor.size).to eq 4
        expect(item.contributor.first).to be_instance_of Relaton::Bib::Contributor
        # editorial group contributor
        eg = item.contributor.last
        expect(eg.role.first.type).to eq "author"
        expect(eg.role.first.description.first.content).to eq "committee"
        expect(eg.organization.subdivision.first).to be_instance_of Relaton::Bib::Subdivision
      end
    end

    context "#fetch_doctype" do
      shared_examples "doctype" do |id, doctype|
        it do
          expect(subject).to receive(:document_id).and_return id
          expect(subject.fetch_doctype.content).to eq doctype
        end
      end

      it_behaves_like "doctype", "JIS A 1301:1994/AMENDMENT 1:2011", "amendment"
    end

    it "#fetch_ics" do
      doc = Nokogiri::HTML(<<~HTML).at("//div[@id='main']/section")
        <div id="main">
          <section>
            <table>
              <tr>
                <th>ICS</th>
                <td class="content">
                                                                                                                        01.040.01<br>
                                                                                    01.120<br>
                                                                                                            </td>
              </tr>
            </table>
          </section>
        </div>
      HTML
      subject.instance_variable_set :@doc, doc
      ics = subject.fetch_ics
      expect(ics).to be_instance_of Array
      expect(ics.size).to eq 2
      expect(ics.first).to be_instance_of Relaton::Bib::ICS
      expect(ics.first.code).to eq "01.040.01"
      expect(ics.last.code).to eq "01.120"
    end
  end
end
