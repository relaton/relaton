require "relaton/itu/data_crawler_r"
require "relaton/itu/data_fetcher"

# The ITU-R crawl prototype (issue #75).
#
# **One cassette per example, deliberately.** VCR re-records per cassette
# *insertion*, so a cassette shared across several examples is truncated to the
# first example's requests when the suite's 7-day `re_record_interval` fires —
# verified: `itu_r_rec_bo` went from 10 interactions to 1 and took 15 examples
# down with it. Each cassette below is therefore owned by exactly one example,
# which is what lets the refresh work as intended (see the cassette conventions
# in the repo-root CLAUDE.md). The counts and dates are what the live pages
# returned when the cassette was recorded; when a refresh makes one fail, ITU
# published something and the expectation is what gets reconciled.
describe Relaton::Itu::DataCrawlerR do
  subject { described_class.new delay: 0 }

  it "enumerates every ITU-R recommendation series",
     :aggregate_failures, vcr: { cassette_name: "itu_r_rec_series_index" } do
    series = subject.series
    expect(series.size).to eq 16
    expect(series.first(4)).to eq %w[BO BR BS BT]
    expect(series).to include "BO"
  end

  it "walks the BO recommendation series end to end",
     :aggregate_failures, vcr: { cassette_name: "itu_r_rec_bo" } do
    docs = subject.documents "BO"
    expect(docs.size).to eq 54
    expect(docs.first[:id]).to eq "R-REC-BO.566"
    expect(docs).to include(
      id: "R-REC-BO.1130", code: "BO.1130",
      title: a_string_matching(/^Systems for digital satellite broadcasting/),
    )
    # the red suppression note is not part of the title
    expect(docs.find { |d| d[:id] == "R-REC-BO.566" }[:title])
      .to eq "Terminology relating to the use of space communication techniques for broadcasting"

    eds = subject.editions "R-REC-BO.1130"
    expect(eds.map { |e| e[:code] }).to eq [
      "BO.1130-5 (02/2026)", "BO.1130-4 (04/2001)", "BO.1130-3 (07/00)",
      "BO.1130-2 (10/99)", "BO.1130-1 (10/95)", "BO.1130-0 (08/94)"
    ]
    expect(eds.first[:id]).to eq "R-REC-BO.1130-5-202602-I"
    expect(eds.first[:status]).to match(/In force/)
    expect(eds.last[:status]).to match(/Superseded/)

    # a single-edition document's code carries no -0, though its id does
    single = subject.editions "R-REC-BO.1212"
    expect(single.size).to eq 1
    expect(single.first[:code]).to eq "BO.1212 (10/95)"
    expect(single.first[:id]).to eq "R-REC-BO.1212-0-199510-I"

    expect(subject.edition("R-REC-BO.1130-5-202602-I")).to eq(
      date: "2026-02-18",
      pdf: "https://www.itu.int/dms_pubrec/itu-r/rec/bo/R-REC-BO.1130-5-202602-I!!PDF-E.pdf",
    )
    # some older editions are Word-only: the deep page is the authority, so no
    # source beats a fabricated !!PDF-E.pdf URL
    expect(subject.edition("R-REC-BO.1130-0-199408-S")).to eq(date: "1994-08-15", pdf: nil)

    # ITU served R-REC-BO.1130-4-200104-S as a 200 with an empty body when the
    # cassette was recorded — a degraded deep crawl must not look clean.
    items = nil
    expect { items = subject.harvest("BO", only: %w[R-REC-BO.1130 R-REC-BO.1212]) }
      .to output(%r{No date on .*BO\.1130-4}).to_stderr_from_any_process

    ids = items.map { |i| i.docidentifier.find(&:primary).content }
    expect(items.size).to eq 7
    expect(items).to all(be_instance_of(Relaton::Itu::ItemData))
    expect(ids).to eq [
      "ITU-R BO.1130-5", "ITU-R BO.1130-4", "ITU-R BO.1130-3", "ITU-R BO.1130-2",
      "ITU-R BO.1130-1", "ITU-R BO.1130-0", "ITU-R BO.1212"
    ]

    bib = items.first
    expect(bib.title.first.content).to match(/^Systems for digital satellite broadcasting/)
    expect(bib.date.first.type).to eq "published"
    expect(bib.date.first.at.to_s).to eq "2026-02-18"
    expect(bib.source.first.content.to_s)
      .to eq "https://www.itu.int/dms_pubrec/itu-r/rec/bo/R-REC-BO.1130-5-202602-I!!PDF-E.pdf"
    expect(bib.ext.doctype.content).to eq "recommendation"
    expect(bib.ext.flavor).to eq "itu"

    # the empty-body edition degrades to the id's YYYYMM rather than losing its date
    expect(items.find { |i| i.docidentifier.find(&:primary).content == "ITU-R BO.1130-4" }
                .date.first.at.to_s).to eq "2001-04"
    # and the PDF-less one stays sourceless
    expect(items.find { |i| i.docidentifier.find(&:primary).content == "ITU-R BO.1130-0" }
                .source).to be_empty

    # What makes this a proof rather than a demo: the harvested ids land on the
    # published dataset's own filenames and every one of them indexes.
    fetcher = Relaton::Itu::DataFetcher.new "data", "yaml"
    expect(ids.map { |id| fetcher.output_file id }).to eq %w[
      data/itu-r-bo-1130-5.yaml data/itu-r-bo-1130-4.yaml data/itu-r-bo-1130-3.yaml
      data/itu-r-bo-1130-2.yaml data/itu-r-bo-1130-1.yaml data/itu-r-bo-1130-0.yaml
      data/itu-r-bo-1212.yaml
    ]
    expect(ids.map { |id| fetcher.pubid id }).to all(be_truthy)
  end

  it "skips the per-edition requests when deep is false",
     :aggregate_failures, vcr: { cassette_name: "itu_r_rec_bo_shallow" } do
    expect(subject).not_to receive(:edition)

    bib = subject.harvest("BO", only: %w[R-REC-BO.1130], deep: false).first
    # Month precision from the id's YYYYMM, and the PDF URL derived from it.
    expect(bib.date.first.at.to_s).to eq "2026-02"
    expect(bib.source.first.content.to_s)
      .to eq "https://www.itu.int/dms_pubrec/itu-r/rec/bo/R-REC-BO.1130-5-202602-I!!PDF-E.pdf"
  end

  it "enumerates the report series (14 — no SNG or V)",
     vcr: { cassette_name: "itu_r_rep_series_index" } do
    expect(subject.series("R-REP")).to eq %w[BO BR BS BT F M P RA RS S SA SF SM TF]
  end

  # Reports live under /pub instead of /rec and date their files rather than
  # their approval — which is what makes them reproduce the published `date:`
  # exactly, where recommendations cannot.
  it "walks the BO report series end to end",
     :aggregate_failures, vcr: { cassette_name: "itu_r_rep_bo" } do
    docs = subject.documents "BO", family: "R-REP"
    expect(docs.size).to eq 36
    # Reports must land in the same cells as recommendations do — the title in
    # the second — or a family would silently harvest blank titles.
    expect(docs.first).to eq(id: "R-REP-BO.215", code: "BO.215",
                             title: "Systems for the broadcasting satellite service (sound and television)")

    eds = subject.editions "R-REP-BO.1227"
    expect(eds.map { |e| e[:code] }).to eq ["BO.1227-2 (1998)", "BO.1227-1 (1994)"]
    expect(eds.first[:title]).to eq "Satellite broadcasting systems of integrated services digital broadcasting"
    expect(eds.first[:status]).to eq "In force (Main)"

    # The page displays "BO.2006-0 (1995)" even though its id is
    # R-REP-BO.2006-1995, so the displayed-code rule needs no family special case.
    expect(subject.editions("R-REP-BO.2006").map { |e| e[:code] }).to eq ["BO.2006-0 (1995)"]

    expect(subject.edition("R-REP-BO.1227-2-1998")).to eq(
      date: "1998-01",
      pdf: "https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BO.1227-2-1998-PDF-E.pdf",
    )

    items = subject.harvest "BO", family: "R-REP", only: %w[R-REP-BO.1227 R-REP-BO.2006]
    expect(items.map { |i| i.docidentifier.find(&:primary).content })
      .to eq ["ITU-R BO.1227-2", "ITU-R BO.1227-1", "ITU-R BO.2006-0"]
    expect(items.map { |i| i.date.first.at.to_s }).to eq %w[1998-01 1994-01 1995-01]
    expect(items.map { |i| i.ext.doctype.content }).to all(eq("technical-report"))
    expect(items.first.source.first.content.to_s)
      .to eq "https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BO.1227-2-1998-PDF-E.pdf"

    fetcher = Relaton::Itu::DataFetcher.new "data", "yaml"
    expect(items.map { |i| fetcher.output_file i.docidentifier.find(&:primary).content })
      .to eq %w[data/itu-r-bo-1227-2.yaml data/itu-r-bo-1227-1.yaml data/itu-r-bo-2006-0.yaml]
  end

  it "falls back to the id's year and derived PDF when deep is false for a report",
     :aggregate_failures, vcr: { cassette_name: "itu_r_rep_bo_shallow" } do
    # A report id ends in its publication year, so shallow mode loses only the
    # month — no per-edition request at all.
    expect(subject).not_to receive(:edition)

    bib = subject.harvest("BO", family: "R-REP", only: %w[R-REP-BO.1227], deep: false).first
    expect(bib.date.first.at.to_s).to eq "1998"
    expect(bib.source.first.content.to_s)
      .to eq "https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BO.1227-2-1998-PDF-E.pdf"
  end

  # /rec/R-REC-M.2083/en, verbatim: one edition, two rows — the second a `…-P`
  # id whose displayed Number is the associated Question. Harvesting it would
  # mint "ITU-R M.5/BL/22" as a Recommendation.
  it "ignores the Question row ITU lists alongside an edition" do
    html = <<~HTML
      <html><body><table>
        <tr><td><a href="./recommendation.asp?lang=en&parent=R-REC-M.2083-0-201509-I"><strong>M.2083-0 (09/2015)</strong></a></td>
            <td>IMT Vision</td><td>In force <b>(Main)</b></td></tr>
        <tr><td><a href="./recommendation.asp?lang=en&parent=R-REC-M.2083-0-201509-P"><strong>M.5/BL/22 (09/2015)</strong></a></td>
            <td>IMT Vision</td><td>In force</td></tr>
      </table></body></html>
    HTML
    page = Mechanize::Page.new(
      URI("https://www.itu.int/rec/R-REC-M.2083/en"), { "content-type" => "text/html" }, html, 200, Mechanize.new
    )
    allow(subject).to receive(:get).and_return page

    expect(subject.editions("R-REC-M.2083").map { |e| e[:code] }).to eq ["M.2083-0 (09/2015)"]
  end

  # /pub/R-REP-BT.2526-1-2024/en, verbatim: the "add to cart" control's href is
  # javascript that embeds both the edition id and PDF-E. Handing it to URI#merge
  # raises URI::InvalidURIError — which killed the whole R-REP-BT series once.
  it "ignores an add-to-cart javascript href that names the PDF" do
    html = <<~HTML
      <html><body>
        <table><tr><td>PDF (acrobat)</td><td>2024-06-01</td></tr></table>
        <a href="\n javascript:addcart('','0','','ENGLISH','electronic','R-REP-BT.2526-1-2024-PDF-E','R-REP-BT.2526-1-2024','2')\n">Add to cart</a>
        <a href="/dms_pub/itu-r/opb/rep/R-REP-BT.2526-1-2024-PDF-E.pdf">PDF</a>
      </body></html>
    HTML
    page = Mechanize::Page.new(
      URI("https://www.itu.int/pub/R-REP-BT.2526-1-2024/en"), { "content-type" => "text/html" }, html, 200, Mechanize.new
    )
    allow(subject).to receive(:get).and_return page

    expect(subject.edition("R-REP-BT.2526-1-2024")).to eq(
      date: "2024-06",
      pdf: "https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BT.2526-1-2024-PDF-E.pdf",
    )
  end

  # Every /pub page carries a QUICK LINKS sidebar whose "Publication Catalogue"
  # entry is itself a `…-PDF-E.pdf`. On a report edition with no English PDF of
  # its own, an unanchored match would hand that catalogue URL to the record —
  # and DataMergeR would then backfill it into the dataset permanently.
  it "ignores the catalogue PDF when a report edition offers none of its own" do
    html = <<~HTML
      <html><body>
        <table><tr><td>PDF (acrobat)</td><td>1990-01-01</td></tr></table>
        <a href="/dms_pub/itu-s/opb/gen/S-GEN-CAT.OL-2025-PDF-E.pdf">Publication Catalogue</a>
      </body></html>
    HTML
    page = Mechanize::Page.new(
      URI("https://www.itu.int/pub/R-REP-BO.215-7-1990/en"),
      { "content-type" => "text/html" }, html, 200, Mechanize.new
    )
    allow(subject).to receive(:get).and_return page

    expect(subject.edition("R-REP-BO.215-7-1990")).to eq(date: "1990-01", pdf: nil)
  end

  it "rejects a family it does not implement" do
    expect { subject.series("R-QUE") }.to raise_error ArgumentError, /unknown ITU-R family/
  end

  context "throttling" do
    # Measured over a 49-minute full run: ITU rate-limits /rec with 503 and /pub
    # with a 302 to notfound.aspx. The second is why 14 report series once came
    # back empty instead of failing.
    subject { described_class.new delay: 0 }

    before { allow(subject).to receive(:sleep) } # don't wait out the backoff

    def page(uri)
      Mechanize::Page.new(URI(uri), { "content-type" => "text/html" }, "<html><body></body></html>", 200, Mechanize.new)
    end

    it "retries a soft block that lands on notfound and succeeds" do
      good = page "https://www.itu.int/pub/R-REP-BO/en"
      expect(subject).to receive(:sleep).at_least(:once)
      expect_any_instance_of(Mechanize).to receive(:get).twice
        .and_return(page("https://www.itu.int/en/publications/pages/notfound.aspx"), good)

      expect(subject.send(:get, "https://www.itu.int/pub/R-REP-BO/en")).to eq good
    end

    it "gives up after RETRIES and raises rather than reporting an empty series" do
      allow_any_instance_of(Mechanize).to receive(:get)
        .and_return page("https://www.itu.int/en/publications/pages/notfound.aspx")

      expect { subject.documents "BO", family: "R-REP" }
        .to raise_error Relaton::RequestError, /Could not access/
    end

    it "retries a transient 503" do
      # What ITU actually returned for /rec under load, verbatim:
      # "503 => Net::HTTPServiceUnavailable for … -- unhandled response"
      good = page "https://www.itu.int/rec/R-REC-BO/en"
      unavailable = Mechanize::Page.new(
        URI("https://www.itu.int/rec/R-REC-BO/en"), { "content-type" => "text/html" }, "", 503, Mechanize.new
      )
      calls = 0
      allow_any_instance_of(Mechanize).to receive(:get) do
        calls += 1
        raise Mechanize::ResponseCodeError.new(unavailable) if calls == 1

        good
      end

      expect(subject.send(:get, "https://www.itu.int/rec/R-REC-BO/en")).to eq good
      expect(calls).to eq 2
    end

    it "wraps a persistent transport failure in a RequestError" do
      allow_any_instance_of(Mechanize).to receive(:get).and_raise SocketError
      expect { subject.series }.to raise_error Relaton::RequestError, /Could not access/
    end
  end
end
