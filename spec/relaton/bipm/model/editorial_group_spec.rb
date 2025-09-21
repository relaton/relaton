# encoding: UTF-8

describe Relaton::Bipm::EditorialGroup do
  context "#from_xml" do
    let(:xml) do
      <<~XML
        <editorialgroup>
          <committee acronym="CCTF" language="fr" script="Latn">Comité Consultatif des Temps et Fréquences</committee>
          <committee acronym="CCEM" language="en" script="Latn">Consultative Committee for Electricity and Magnetism</committee>
          <workgroup acronym="WG1">Working Group 1</workgroup>
        </editorialgroup>
      XML
    end

    it "parses XML to EditorialGroup object" do
      eg = Relaton::Bipm::EditorialGroup.from_xml xml
      expect(eg.committee.size).to eq 2
      expect(eg.committee[0].acronym).to eq "CCTF"
      expect(eg.committee[0].content).to eq "Comité Consultatif des Temps et Fréquences"
      expect(eg.committee[0].language).to eq "fr"
      expect(eg.committee[0].script).to eq "Latn"
      expect(eg.committee[1].acronym).to eq "CCEM"
      expect(eg.committee[1].content).to eq "Consultative Committee for Electricity and Magnetism"
      expect(eg.committee[1].language).to eq "en"
      expect(eg.committee[1].script).to eq "Latn"
      expect(eg.workgroup.size).to eq 1
      expect(eg.workgroup[0].acronym).to eq "WG1"
      expect(eg.workgroup[0].content).to eq "Working Group 1"
    end
  end
end
