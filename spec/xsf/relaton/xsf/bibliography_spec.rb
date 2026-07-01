describe Relaton::Xsf::Bibliography do
  context "get" do
    it "successful", vcr: "get_successful" do
      expect do
        file = "fixtures/bibdata.xml"
        bib = Relaton::Xsf::Bibliography.get "XEP 0001"
        xml = bib.to_xml bibdata: true
        File.write file, xml, encoding: "UTF-8" unless File.exist? file
        expect(bib).to be_instance_of Relaton::Xsf::ItemData
        expect(bib.docidentifier.first.content).to eq "XEP 0001"
        expect(xml).to be_equivalent_to File.read(file, encoding: "UTF-8").gsub(
          /(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s
        )
      end.to output(
        include("[relaton-xsf] INFO: (XEP 0001) Fetching from Relaton repository ...",
                "[relaton-xsf] INFO: (XEP 0001) Found: `XEP 0001`"),
      ).to_stderr_from_any_process
    end

    it "not found", vcr: "get_not_found" do
      expect { Relaton::Xsf::Bibliography.get "XEP nope" }.to output(
        /\[relaton-xsf\] INFO: \(XEP nope\) Not found\./,
      ).to_stderr_from_any_process
    end
  end
end
