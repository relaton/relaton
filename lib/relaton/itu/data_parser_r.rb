module Relaton
  module Itu
    # Map one normalized ITU-R row to an ItemData.
    #
    # The row comes from DataCrawlerR's three-level `/pub` + `/rec` crawl (issue
    # #75), which replaced the decommissioned RunSearch result hash this module
    # used to consume. The split mirrors DataParserT: the crawler owns the HTTP
    # and the page scraping, this module owns the mapping, so it stays a pure
    # unit with no network in its specs. Row keys:
    #
    #   :id      "R-REC-BO.1130-5-202602-I"  page id
    #   :code    "BO.1130-5 (02/2026)"       displayed code -> primary docid
    #   :title   English title
    #   :status  "In force (Main)" | "Superseded" | …   (scraped, not modelled)
    #   :date    "2026-02-18" | "2026-02"    approval date for a Recommendation,
    #                                        publication date for a Report
    #   :url     the record's landing page
    #   :pdf     absolute dms_pubrec/dms_pub URL
    #   :family  "R-REC" | "R-REP" | "R-QUE" | "R-RES" | "R-HDB"
    module DataParserR
      extend self

      FAMILY_DOCTYPE = {
        "R-REC" => "recommendation",
        "R-REP" => "technical-report",
        "R-QUE" => "question",
        "R-RES" => "resolution",
        "R-HDB" => "handbook",
      }.freeze

      #
      # Parse an ITU-R document from a normalized crawler row.
      #
      # @param row [Hash] see the key list above
      # @param errors [Hash] shared error tally, `&&=`-narrowed per field so a
      #   field that succeeded once is never reported as missing
      #
      # @return [Relaton::Itu::ItemData, nil] nil when the family is unknown
      #
      def parse(row, errors = {})
        doctype = fetch_doctype(row, errors)
        return unless doctype

        docid = fetch_docid(row, errors)
        # A record with no primary docid can't be written or indexed —
        # DataFetcher#write_file reads `docidentifier.find(&:primary).content` —
        # so drop it here, as DataParserT does.
        return if docid.empty?

        Relaton::Itu::ItemData.new(
          docidentifier: docid, title: fetch_title(row, errors),
          date: fetch_date(row, errors), language: ["en"],
          source: fetch_source(row, errors), script: ["Latn"],
          type: "standard", ext: Relaton::Itu::Ext.new(doctype: doctype, flavor: "itu"),
        )
      end

# Each ITU-R family spells its identifier differently, and the published
# dataset is the authority on which spelling. Verified against
# relaton-data-itu:
#
#   R-REC  the displayed code    "BO.1130-5 (02/2026)" -> ITU-R BO.1130-5
#   R-REP  the same, prefixed    "BO.1227-2 (1998)"    -> Report ITU-R BO.1227-2
#   R-QUE  the same, + a colon   "202-2/1"             -> ITU-R 202-2/1:
#   R-RES  the **page id**       R-RES-R.1-9-2023      -> ITU-R R.1-9
#
# Two of those need saying out loud. A **Report** is prefixed because
# Recommendations and Reports number independently, so `ITU-R BT.2020-1`
# alone names two different documents (pubid #327 types the prefixed form
# `pubid:itu:report`, and `output_file` sends it to `report-itu-r-*.yaml`
# instead of colliding). A **Resolution** cannot use its displayed code at
# all: the page renders "Res.1-9 (2023)" while the published record is
# `ITU-R R.1-9`, which only the id carries.
#
# The code is NBSP-folded first — the cells are padded with `&nbsp;`, which
# neither `\s` nor String#strip match, and an NBSP left in a docid
# sanitizes into the filename and defeats `Pubid::Itu`.
#
# @param row [Hash]
# @return [String, nil] nil when the row carries nothing to build from
def family_docid(row)
        # " " spelled as an escape on purpose: a literal NBSP here is invisible
        # and has been silently lost by tooling before.
        code = row[:code].to_s.tr(" ", " ").sub(/\s*\(.*\z/m, "").strip
  return "ITU-R #{resolution_number row}" if row[:family] == "R-RES"
  return nil if code.empty?

  case row[:family]
  when "R-REP" then "Report ITU-R #{code}"
  when "R-QUE" then "ITU-R #{code}:"
  else "ITU-R #{code}"
  end
end

# "R-RES-R.1-9-2023" -> "R.1-9"
#
# @param row [Hash]
# @return [String, nil]
def resolution_number(row)
  n = row[:id].to_s.sub(/\AR-RES-/, "").sub(/-(?:19|20)\d{2}\z/, "")
  n.empty? ? nil : n
end

# @param row [Hash]
# @return [Array<Relaton::Bib::Docidentifier>]
def fetch_docid(row, errors = {})
  content = family_docid row
  if content.nil? || content == "ITU-R "
    errors[:docid] &&= true
    return []
  end

  r = [Docidentifier.new(type: "ITU", content: content, primary: true)]
  errors[:docid] &&= r.empty?
  r
end

      # @param row [Hash]
      # @return [Array<Relaton::Bib::Title>]
      def fetch_title(row, errors = {})
        content = row[:title].to_s.strip
        if content.empty?
          errors[:title] &&= true
          return []
        end

        r = [Relaton::Bib::Title.new(type: "main", content: content, language: "en", script: "Latn")]
        errors[:title] &&= r.empty?
        r
      end

      # Whatever date the crawler could see: for a **Recommendation** that is the
      # approval date — *not* the publication date the preserved records carry,
      # which died with RunSearch (issue #75), which is why DataMergeR never
      # rewrites one — and for a **Report** it is the publication date itself,
      # read off the edition page's posted files. Day precision when it comes
      # from the page, month or year precision when derived from the page id.
      #
      # @param row [Hash]
      # @return [Array<Relaton::Bib::Date>]
      def fetch_date(row, errors = {})
        date = row[:date].to_s.strip
        if date.empty?
          errors[:date] &&= true
          return []
        end

        r = [Relaton::Bib::Date.new(type: "published", at: date)]
        errors[:date] &&= r.empty?
        r
      end

      # @param row [Hash]
      # @return [Array<Relaton::Bib::Uri>]
      def fetch_source(row, errors = {})
        pdf = row[:pdf].to_s.strip
        if pdf.empty?
          errors[:source] &&= true
          return []
        end

        r = [Relaton::Bib::Uri.new(type: "pdf", content: pdf)]
        errors[:source] &&= r.empty?
        r
      end

      # @param row [Hash]
      # @return [Relaton::Itu::Doctype, nil]
      def fetch_doctype(row, errors = {})
        mapped = FAMILY_DOCTYPE[row[:family]]
        unless mapped
          errors[:doctype] &&= true
          return
        end

        errors[:doctype] &&= false
        Doctype.new(content: mapped)
      end
    end
  end
end
