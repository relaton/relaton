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

    # A WES (Japan Welding Engineering Society) page from the JWES list
    # (relaton-jis#18). It has the JIS layout but no 原案作成団体 row.
    context "#fetch a WES document" do
      let(:doc) { Nokogiri::HTML File.read "fixtures/wes_7700_1_2019.html", encoding: "UTF-8" }
      let(:item) { subject.fetch }

      before do
        agent = subject.instance_variable_get :@agent
        expect(agent).to receive(:get)
          .with("https://document.url").and_return doc
      end

      it "reads the WES identifier" do
        docid = item.docidentifier.first
        expect(docid.content).to eq "WES 7700-1:2019"
        expect(docid.type).to eq "WES"
        expect(docid.primary).to be true
        expect(item.ext.structuredidentifier.type).to eq "WES"
        expect(item.ext.structuredidentifier.project_number.content).to eq "7700"
      end

      it "reads the page fields" do
        expect(item.title.map(&:content)).to eq [
          "圧力設備の溶接補修　第１部：一般",
          "Repair welding of pressure equipment Part 1: General",
        ]
        expect(item.date.map { |d| [d.type, d.at.to_s] }).to eq [%w[issued 2019-06-01]]
        expect(item.status.stage.content).to eq "valid"
        expect(item.ext.flavor).to eq "jis"
      end

      it "takes the JIS doctype of its form" do
        expect(item.ext.doctype.content).to eq "japanese-industrial-standard"
      end

      it "writes XML that the JIS grammar accepts" do
        file = File.join Dir.mktmpdir("relaton-jis-wes"), "wes.xml"
        File.write file, Relaton::Jis::Bibdata.to_xml(item), encoding: "UTF-8"
        schema = Relaxng.new "../../grammar/relaton-jis-compile.rng"
        expect(schema.validate(file)).to eq []
      end

      it "is authored and published by JWES" do
        orgs = item.contributor.map do |c|
          [c.role.map(&:type), c.organization.name.map(&:content)]
        end
        names = ["一般社団法人日本溶接協会", "Japan Welding Engineering Society"]
        expect(orgs).to eq [[["author"], names], [["publisher"], names]]
      end
    end

    context "#fetch_doctype" do
      shared_examples "doctype" do |id, doctype|
        it do
          expect(subject).to receive(:document_id).at_least(:once).and_return id
          expect(subject.fetch_doctype&.content).to eq doctype
        end
      end

      it_behaves_like "doctype", "JIS A 1301:1994/AMENDMENT 1:2011", "amendment"
      it_behaves_like "doctype", "TR Z 0010:2008", "technical-report"
      # The JIS grammar requires a doctype and has no WES value, so a WES
      # record takes the JIS value of its form.
      it_behaves_like "doctype", "WES 7700-1:2019", "japanese-industrial-standard"
      it_behaves_like "doctype", "WES 1112(E):2022", "japanese-industrial-standard"
      it_behaves_like "doctype", "WES 0001:2021/AMENDMENT 1:2025", "amendment"
      it_behaves_like "doctype", "WES 3003(E):1995/AMENDMENT 1:2025", "amendment"
      it_behaves_like "doctype", "WES TR 2032:2024", "technical-report"
      it_behaves_like "doctype", "WES TS 2816:2015", "technical-specification"
    end

    context "#fetch_docnumber" do
      shared_examples "docnumber" do |id, number|
        it "#{id} -> #{number}" do
          allow(subject).to receive(:document_id).and_return id
          expect(subject.fetch_docnumber).to eq number
        end
      end

      it_behaves_like "docnumber", "JIS X 0208:1997", "X0208"
      it_behaves_like "docnumber", "TR Z 0010:2008", "Z0010"
      it_behaves_like "docnumber", "WES 7700-1:2019", "7700"
      it_behaves_like "docnumber", "WES 1112(E):2022", "1112"
      it_behaves_like "docnumber", "WES TR 2032:2024", "2032"
      it_behaves_like "docnumber", "WES TS 2816:2015", "2816"
    end

    it "#fetch_ics" do
      doc = Nokogiri::HTML(<<~HTML).at_xpath("//div[@id='main']/section")
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
