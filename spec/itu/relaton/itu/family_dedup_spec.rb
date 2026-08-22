require "relaton/itu/recommendation_parser"
require "relaton/itu/family_cache"

# The ITU-T request de-duplication.
#
# `searchRecs` runs with `main_edition_flag=0`, so it returns one row per
# EDITION — and two of the four enrichment endpoints answer for the whole
# recommendation. H.264 has 21 editions, so the crawl asked ITU the same
# question 21 times. Verified against the recorded bytes in
# `spec/itu/vcr_cassettes/itu_t_h_264.yml`: `getRecEditions?idrec=16818` and
# `?idrec=14659` return byte-identical 21-row payloads, and both `rec.aspx`
# recordings render "ITU-T Study Group 21".
#
# Stubbed rather than cassette-backed on purpose: this file's convention is one
# cassette per example (a shared cassette gets truncated to the first example's
# requests when the 7-day re-record fires), and what is under test here is the
# de-duplication mechanism, not ITU's bytes.
RSpec.describe "ITU-T family de-duplication" do
  # Two sibling editions of one recommendation, exactly as getRecEditions
  # returns them: each row carries its own idrec, and the list is the same list
  # whichever sibling you ask about.
  let(:rows) do
    [{ "idrec" => 16_818, "Version" => "16", "rec_name" => "H.264" },
     { "idrec" => 14_659, "Version" => "13", "rec_name" => "H.264" }]
  end
  let(:agent) { instance_double Mechanize }
  let(:cache) { Relaton::Itu::FamilyCache.new }

  def parser(idrec, cache)
    Relaton::Itu::RecommendationParser.new agent, idrec, false, cache: cache
  end

  before do
    allow(agent).to receive(:get).with(a_string_including("getRecEditions"))
      .and_return(double("resp", body: rows.to_json))
  end

  it "asks ITU once for a family the crawl walks edition by edition" do
    expect(agent).to receive(:get).with(a_string_including("getRecEditions")).once
      .and_return(double("resp", body: rows.to_json))

    first = parser(16_818, cache).send(:editions)
    second = parser(14_659, cache).send(:editions)
    expect(second).to eq first
    expect(cache.stats).to include(hits: 1, misses: 1)
  end

  it "still picks the right edition out of the shared list" do
    # The sharing is only safe because each parser selects its own row from the
    # family's list rather than trusting the response wholesale.
    expect(parser(16_818, cache).fetch_edition).to eq "16"
    expect(parser(14_659, cache).fetch_edition).to eq "13"
  end

  it "refuses to share a response that does not list the idrec it asked for" do
    # If the endpoint's contract ever changes, losing the de-duplication is the
    # cheap failure; handing a whole family another recommendation's metadata is
    # the expensive one, and nothing downstream would catch it.
    allow(agent).to receive(:get).with(a_string_including("getRecEditions"))
      .and_return(double("resp", body: [{ "idrec" => 999 }].to_json))

    parser(16_818, cache).send(:editions)
    # Only its own key is cached — idrec 999 was NOT warmed with this payload,
    # so a later row for 999 fetches its own answer instead of inheriting one
    # that was never claimed to be its.
    expect(cache.stats[:entries]).to eq 1
    expect(agent).to receive(:get).with(a_string_including("getRecEditions"))
      .and_return(double("resp", body: [{ "idrec" => 999 }].to_json))
    parser(999, cache).send(:editions)
  end

  it "shares the study group across the family, one page fetch instead of many" do
    # rec.aspx is the single most expensive request per record — ~90-240 KB of
    # HTML plus a DOM parse — and the study group it carries is a property of
    # the recommendation, not of the edition.
    page = double "page"
    allow(page).to receive(:at).and_return(double("wg", text: "Study Group 21"))
    expect(agent).to receive(:get).with(a_string_including("rec.aspx")).once.and_return(page)

    expect(parser(16_818, cache).fetch_workgroup).to eq "Study Group 21"
    expect(parser(14_659, cache).fetch_workgroup).to eq "Study Group 21"
  end

  it "changes nothing on the live lookup path" do
    # The runtime boundary: Scraper builds its parser without a cache, so every
    # lookup issues its own requests and retains no state between calls.
    null = Relaton::Itu::NullCache.instance
    expect(null.caching?).to be false
    expect(agent).to receive(:get).with(a_string_including("getRecEditions")).twice
      .and_return(double("resp", body: rows.to_json))

    parser(16_818, null).send(:editions)
    parser(14_659, null).send(:editions)
  end

  it "does not reach for the family when there is no cache" do
    # #family_id reads #editions, so keying the workgroup on it unconditionally
    # would add a getRecEditions request to a runtime lookup that never needed
    # one. The null cache short-circuits before the key is built.
    null = Relaton::Itu::NullCache.instance
    page = double "page"
    allow(page).to receive(:at).and_return(double("wg", text: "Study Group 21"))
    expect(agent).not_to receive(:get).with(a_string_including("getRecEditions"))
    expect(agent).to receive(:get).with(a_string_including("rec.aspx")).and_return(page)

    expect(parser(16_818, null).fetch_workgroup).to eq "Study Group 21"
  end
end
