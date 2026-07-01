# frozen_string_literal: true

RSpec.describe Relaton::Doi::Parser do
  describe "#fetch_crossref" do
    let(:parser) { described_class.new({}) }
    let(:query) { "test+query" }
    let(:filter) { "type:book" }
    let(:url) { "https://api.crossref.org/works?query=#{query}&filter=#{filter}" }
    let(:items) { [{ "title" => ["Test"] }] }
    let(:success_body) { { "message" => { "items" => items } }.to_json }
    let(:agent) { instance_double(Mechanize) }

    before do
      allow(Relaton::Doi::Crossref).to receive(:agent).and_return(agent)
    end

    context "when response is 2xx" do
      it "returns items array" do
        page = double(body: success_body)
        expect(agent).to receive(:get).with(url).and_return(page)
        expect(parser.fetch_crossref(query: query, filter: filter)).to eq items
      end
    end

    context "when response is 4xx" do
      it "returns nil" do
        error = Mechanize::ResponseCodeError.new(
          double(code: "404", body: "Not found"),
        )
        expect(agent).to receive(:get).with(url).and_raise(error)
        expect(parser.fetch_crossref(query: query, filter: filter)).to be_nil
      end
    end

    context "when response is 5xx" do
      it "raises RequestError" do
        error = Mechanize::ResponseCodeError.new(
          double(code: "500", body: "Internal Server Error"),
        )
        allow(error).to receive(:page).and_return(
          double(body: "Internal Server Error"),
        )
        expect(agent).to receive(:get).with(url).and_raise(error)
        expect do
          parser.fetch_crossref(query: query, filter: filter)
        end.to raise_error(Relaton::RequestError, /Crossref request failed: 500/)
      end
    end

    context "when network error occurs" do
      it "retries MAX_RETRIES times then raises RequestError" do
        expect(agent).to receive(:get).with(url)
          .exactly(Relaton::Doi::Parser::MAX_RETRIES + 1).times
          .and_raise(Errno::ECONNREFUSED.new("Connection refused"))
        expect do
          parser.fetch_crossref(query: query, filter: filter)
        end.to raise_error(Relaton::RequestError, /Crossref network error after 3 retries/)
      end

      it "returns result if succeeds after retry" do
        page = double(body: success_body)
        call_count = 0
        allow(agent).to receive(:get).with(url) do
          call_count += 1
          raise Errno::ECONNREFUSED, "Connection refused" if call_count < 3

          page
        end
        expect(parser.fetch_crossref(query: query, filter: filter)).to eq items
      end
    end

    context "when JSON parsing fails" do
      it "raises RequestError" do
        page = double(body: "invalid json")
        expect(agent).to receive(:get).with(url).and_return(page)
        expect do
          parser.fetch_crossref(query: query, filter: filter)
        end.to raise_error(Relaton::RequestError, /Crossref JSON parsing error/)
      end
    end
  end

  describe "#parse_title" do
    subject(:titles) { parser.parse_title }

    let(:parser) { described_class.new(src) }

    context "when title is a non-empty array" do
      context "with title only" do
        let(:src) { { "title" => ["Main Title"] } }

        it "returns one main title" do
          expect(titles.size).to eq 1
          expect(titles[0].content).to eq "Main Title"
          expect(titles[0].type).to eq "main"
        end
      end

      context "with title and subtitle" do
        let(:src) { { "title" => ["Main"], "subtitle" => ["Sub"] } }

        it "returns main and subtitle titles" do
          expect(titles.size).to eq 2
          expect(titles[0].content).to eq "Main"
          expect(titles[0].type).to eq "main"
          expect(titles[1].content).to eq "Sub"
          expect(titles[1].type).to eq "subtitle"
        end
      end

      context "with title and short-title" do
        let(:src) { { "title" => ["Main"], "short-title" => ["Short"] } }

        it "returns main and short titles" do
          expect(titles.size).to eq 2
          expect(titles[0].content).to eq "Main"
          expect(titles[0].type).to eq "main"
          expect(titles[1].content).to eq "Short"
          expect(titles[1].type).to eq "short"
        end
      end

      context "with title, subtitle, and short-title" do
        let(:src) do
          { "title" => ["Main"], "subtitle" => ["Sub"], "short-title" => ["Short"] }
        end

        it "returns all three titles in order" do
          expect(titles.size).to eq 3
          expect(titles.map(&:type)).to eq %w[main subtitle short]
          expect(titles.map(&:content)).to eq %w[Main Sub Short]
        end
      end

      context "with multiple titles" do
        let(:src) { { "title" => ["A", "B"] } }

        it "returns multiple main titles" do
          expect(titles.size).to eq 2
          expect(titles.map(&:type)).to eq %w[main main]
          expect(titles.map(&:content)).to eq %w[A B]
        end
      end

      context "with str_cleanup applied" do
        let(:src) { { "title" => ["  Trailing comma, "] } }

        it "cleans up the title content" do
          expect(titles.size).to eq 1
          expect(titles[0].content).to eq "Trailing comma"
        end
      end

      context "with HTML-entity-encoded JATS title wrapper" do
        let(:src) do
          { "title" => ["&lt;title&gt;Test target&lt;/title&gt;"] }
        end

        it "decodes entities and strips the JATS title wrapper" do
          expect(titles.size).to eq 1
          expect(titles[0].content).to eq "Test target"
        end
      end

      context "with HTML-entity-encoded characters in the title" do
        let(:src) { { "title" => ["Caf&#233; &amp; Bar"] } }

        it "decodes HTML entities" do
          expect(titles.size).to eq 1
          expect(titles[0].content).to eq "Café & Bar"
        end
      end

      context "with a plain title containing no entities" do
        let(:src) { { "title" => ["Plain title"] } }

        it "leaves the title unchanged" do
          expect(titles.size).to eq 1
          expect(titles[0].content).to eq "Plain title"
        end
      end
    end

    context "when project is a non-empty array" do
      context "with single project and single project-title" do
        let(:src) do
          { "project" => [{ "project-title" => [{ "title" => "Proj" }] }] }
        end

        it "returns one title" do
          expect(titles.size).to eq 1
          expect(titles[0].content).to eq "Proj"
          expect(titles[0].type).to eq "main"
        end
      end

      context "with multiple projects" do
        let(:src) do
          {
            "project" => [
              { "project-title" => [{ "title" => "Proj1" }] },
              { "project-title" => [{ "title" => "Proj2" }] },
            ],
          }
        end

        it "returns one title per project" do
          expect(titles.size).to eq 2
          expect(titles.map(&:content)).to eq %w[Proj1 Proj2]
        end
      end

      context "with project that has no project-title" do
        let(:src) { { "project" => [{}] } }

        it "returns empty array" do
          expect(titles).to eq []
        end
      end
    end

    context "when container-title has more than one element" do
      context "with two container-titles" do
        let(:src) { { "container-title" => ["Series", "Journal"] } }

        it "returns titles from all but the last element" do
          expect(titles.size).to eq 1
          expect(titles[0].content).to eq "Series"
        end
      end

      context "with three container-titles" do
        let(:src) { { "container-title" => ["A", "B", "C"] } }

        it "returns titles from all but the last element" do
          expect(titles.size).to eq 2
          expect(titles.map(&:content)).to eq %w[A B]
        end
      end
    end

    context "when none of the branches match" do
      context "with empty source hash" do
        let(:src) { {} }

        it "returns empty array" do
          expect(titles).to eq []
        end
      end

      context "with title as empty array" do
        let(:src) { { "title" => [] } }

        it "returns empty array" do
          expect(titles).to eq []
        end
      end
    end
  end

  describe "#create_affiliation" do
    let(:parser) { described_class.new({}) }

    context "when person has one affiliation" do
      it "returns one Affiliation with the correct organization name" do
        person = { "affiliation" => [{ "name" => "MIT" }] }
        result = parser.create_affiliation(person)
        expect(result.size).to eq 1
        expect(result[0]).to be_a Relaton::Bib::Affiliation
        expect(result[0].organization.name.first.content).to eq "MIT"
      end
    end

    context "when person has multiple affiliations" do
      it "returns an Affiliation for each entry" do
        person = { "affiliation" => [{ "name" => "MIT" }, { "name" => "Stanford" }] }
        result = parser.create_affiliation(person)
        expect(result.size).to eq 2
        expect(result.map { |a| a.organization.name.first.content }).to eq %w[MIT Stanford]
      end
    end

    context "when person has no affiliation key" do
      it "returns an empty array" do
        expect(parser.create_affiliation({})).to eq []
      end
    end

    context "when person has nil affiliation" do
      it "returns an empty array" do
        expect(parser.create_affiliation({ "affiliation" => nil })).to eq []
      end
    end

    context "when person has empty affiliation array" do
      it "returns an empty array" do
        expect(parser.create_affiliation({ "affiliation" => [] })).to eq []
      end
    end
  end

  describe "#nameprefix" do
    let(:parser) { described_class.new({}) }

    context "when person has a prefix" do
      it "returns an array with one LocalizedString" do
        result = parser.nameprefix("prefix" => "Dr.")
        expect(result.size).to eq 1
        expect(result[0]).to be_a Relaton::Bib::LocalizedString
        expect(result[0].content).to eq "Dr."
        expect(result[0].language).to eq "en"
        expect(result[0].script).to eq "Latn"
      end
    end

    context "when person has no prefix key" do
      it "returns an empty array" do
        expect(parser.nameprefix({})).to eq []
      end
    end

    context "when person has nil prefix" do
      it "returns an empty array" do
        expect(parser.nameprefix("prefix" => nil)).to eq []
      end
    end
  end

  describe "#completename" do
    let(:parser) { described_class.new({}) }

    context "when person has a name" do
      it "returns a LocalizedString with correct content, language, and script" do
        result = parser.completename("name" => "John Doe")
        expect(result).to be_a Relaton::Bib::LocalizedString
        expect(result.content).to eq "John Doe"
        expect(result.language).to eq "en"
        expect(result.script).to eq "Latn"
      end
    end

    context "when person has no name key" do
      it "returns nil" do
        expect(parser.completename({})).to be_nil
      end
    end

    context "when person has nil name" do
      it "returns nil" do
        expect(parser.completename("name" => nil)).to be_nil
      end
    end
  end

  describe "#nameaddition" do
    let(:parser) { described_class.new({}) }

    context "when person has a suffix" do
      it "returns an array with one LocalizedString" do
        result = parser.nameaddition("suffix" => "Jr.")
        expect(result.size).to eq 1
        expect(result[0]).to be_a Relaton::Bib::LocalizedString
        expect(result[0].content).to eq "Jr."
        expect(result[0].language).to eq "en"
        expect(result[0].script).to eq "Latn"
      end
    end

    context "when person has no suffix key" do
      it "returns an empty array" do
        expect(parser.nameaddition({})).to eq []
      end
    end

    context "when person has nil suffix" do
      it "returns an empty array" do
        expect(parser.nameaddition("suffix" => nil)).to eq []
      end
    end
  end

  describe "#parse_place" do
    context "when publisher-location is a city and a country" do
      let(:parser) { described_class.new("publisher-location" => "New York, USA") }

      it "returns a Place with city and country" do
        result = parser.parse_place
        expect(result.size).to eq 1
        expect(result[0].city).to eq "New York"
        expect(result[0].country.first.content).to eq "USA"
      end
    end

    context "when publisher-location is a city and an uppercase region" do
      let(:parser) { described_class.new("publisher-location" => "Springfield, IL") }

      it "returns a Place with city and region" do
        result = parser.parse_place
        expect(result.size).to eq 1
        expect(result[0].city).to eq "Springfield"
        expect(result[0].region.first.content).to eq "IL"
      end
    end

    context "when publisher-location is a city only" do
      let(:parser) { described_class.new("publisher-location" => "London") }

      it "returns a Place with city only" do
        result = parser.parse_place
        expect(result.size).to eq 1
        expect(result[0].city).to eq "London"
      end
    end

    context "when publisher-location has two mixed-case parts" do
      let(:parser) { described_class.new("publisher-location" => "Cambridge, Massachusetts") }

      it "returns two Places, one for each part" do
        result = parser.parse_place
        expect(result.size).to eq 2
        expect(result[0].city).to eq "Cambridge"
        expect(result[1].city).to eq "Massachusetts"
      end
    end

    context "when publisher-location has duplicate city names" do
      let(:parser) { described_class.new("publisher-location" => "London, London") }

      it "returns a single Place" do
        result = parser.parse_place
        expect(result.size).to eq 1
        expect(result[0].city).to eq "London"
      end
    end

    context "when publisher-location is nil and no fetch_location result" do
      let(:parser) { described_class.new({}) }

      before do
        allow(parser).to receive(:fetch_location).and_return(nil)
      end

      it "returns an empty array" do
        expect(parser.parse_place).to eq []
      end
    end

    context "when publisher-location has trailing comma" do
      let(:parser) { described_class.new("publisher-location" => "Berlin, ") }

      it "returns a single Place with cleaned city" do
        result = parser.parse_place
        expect(result.size).to eq 1
        expect(result[0].city).to eq "Berlin"
      end
    end
  end

  describe "#parse_series" do
    context "when container-title is absent" do
      let(:parser) { described_class.new({}) }

      it "returns an empty array" do
        expect(parser.parse_series).to eq []
      end
    end

    context "when type is report-component" do
      let(:parser) { described_class.new("type" => "report-component", "container-title" => ["Series"]) }

      it "returns an empty array" do
        expect(parser.parse_series).to eq []
      end
    end

    context "when source has title and container-title" do
      let(:parser) { described_class.new("title" => ["Main"], "container-title" => ["Series A", "Series B"]) }

      it "returns a Series for each container-title" do
        result = parser.parse_series
        expect(result.size).to eq 2
        expect(result.map { |s| s.title.first.content }).to eq ["Series A", "Series B"]
      end
    end

    context "when source has project and container-title" do
      let(:src) do
        {
          "title" => [],
          "project" => [{ "project-title" => [{ "title" => "Proj" }] }],
          "container-title" => ["Series X"],
        }
      end
      let(:parser) { described_class.new(src) }

      it "returns a Series for each container-title" do
        result = parser.parse_series
        expect(result.size).to eq 1
        expect(result[0].title.first.content).to eq "Series X"
      end
    end

    context "when no title/project but container-title has multiple elements" do
      let(:parser) { described_class.new("title" => [], "container-title" => ["First", "Second"]) }

      it "returns a Series for the last container-title only" do
        result = parser.parse_series
        expect(result.size).to eq 1
        expect(result[0].title.first.content).to eq "Second"
      end
    end

    context "when no title/project but container-title has multiple elements and short-container-title" do
      let(:src) do
        {
          "title" => [],
          "container-title" => ["First", "Second"],
          "short-container-title" => ["F", "S"],
        }
      end
      let(:parser) { described_class.new(src) }

      it "returns a Series with abbreviation from the last short-container-title" do
        result = parser.parse_series
        expect(result.size).to eq 1
        expect(result[0].title.first.content).to eq "Second"
        expect(result[0].abbreviation.content).to eq "S"
      end
    end

    context "when no title/project and container-title has one element" do
      let(:parser) { described_class.new("title" => [], "container-title" => ["Only"]) }

      it "returns an empty array" do
        expect(parser.parse_series).to eq []
      end
    end
  end
end
