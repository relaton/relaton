require "fileutils"
require "yaml"
require "date"

module Relaton::Jcgm
  # Harvests JCGM meeting proceedings from the `jcgm/meetings-{en,fr}` dirs of a
  # local checkout of metanorma/bipm-data-outcomes and writes one Relaton YAML
  # per meeting into `<output>/jcgm/meeting/<num>.yaml`, indexing each by its
  # `Pubid::Jcgm` meeting identifier.
  #
  # This is the JCGM-only slice of `Relaton::Bipm::DataOutcomesParser`: JCGM
  # meetings carry no sub-resolutions and no parts, so the resolution/part
  # machinery is dropped. The meeting docnumber's ordinal ("11st"/"12nd"/"13rd"
  # — a naive last-digit rule with no teens exception) is delegated to
  # `Pubid::Jcgm::Identifiers::Meeting.ordinal`, the single source of truth, so
  # the printed form round-trips through pubid.
  class MeetingsParser
    SOURCE_ROOT = "bipm-data-outcomes".freeze
    BODY = "JCGM".freeze
    GH_SRC = "https://raw.githubusercontent.com/metanorma/bipm-data-outcomes/".freeze

    def self.parse(data_fetcher)
      new(data_fetcher).parse
    end

    def initialize(data_fetcher)
      @data_fetcher = data_fetcher
    end

    def parse
      Dir[File.join(SOURCE_ROOT, "jcgm", "meetings-en", "*.{yml,yaml}")].sort.each do |en_file|
        fetch_meeting en_file
      end
    end

    private

    def fetch_meeting(en_file)
      en, fr, fr_file = read_files en_file
      md_en = en["metadata"]
      md_fr = fr && fr["metadata"]
      num = md_en["identifier"].to_s
      date = md_en["date"].to_s
      docnum = meeting_docnum num, date
      id = "JCGMMeeting#{num}#{::Date.parse(date).year}"

      outdir = File.join @data_fetcher.output, "jcgm", "meeting"
      FileUtils.mkdir_p outdir
      path = File.join outdir, "#{num}.#{@data_fetcher.ext}"

      item = ItemData.new(**meeting_hash(md_en, md_fr, num, id, docnum,
                                         meeting_links(en_file, fr_file), en["pdf"]))
      @data_fetcher.write_file path, item
      @data_fetcher.add_to_index docnum, path
    end

    # Read English + French metadata (the French file mirrors the path with
    # `en` -> `fr`). `Date`/`Time` are permitted because the source may write
    # an unquoted `date:` scalar; the date is coerced to a string downstream.
    def read_files(en_file)
      fr_file = en_file.sub "en", "fr"
      en = load_yaml en_file
      fr = File.exist?(fr_file) ? load_yaml(fr_file) : nil
      [en, fr, (fr && fr_file)]
    end

    def load_yaml(file)
      YAML.safe_load File.read(file, encoding: "UTF-8"), permitted_classes: [Date, Time]
    end

    # "JCGM 17th Meeting (2012)" — ordinal via pubid's Meeting.ordinal.
    def meeting_docnum(num, date)
      year = ::Date.parse(date).year
      "#{BODY} #{::Pubid::Jcgm::Identifiers::Meeting.ordinal(num)} Meeting (#{year})"
    end

    def meeting_hash(md_en, md_fr, num, id, docnum, src, pdf) # rubocop:disable Metrics/MethodLength
      {
        id: id,
        type: "proceedings",
        title: titles(md_en, md_fr),
        place: [Relaton::Bib::Place.new(city: "Paris")],
        date: date(md_en["date"]),
        docidentifier: docids(docnum),
        docnumber: docnum,
        source: links(md_en, md_fr, src, pdf),
        language: %w[en fr],
        script: ["Latn"],
        contributor: [bipm_contrib],
        ext: ext(num),
      }
    end

    def titles(md_en, md_fr)
      result = []
      result << title(md_en["title"], "en") if md_en && md_en["title"]
      result << title(md_fr["title"], "fr") if md_fr && md_fr["title"]
      result
    end

    def title(content, language)
      content = content.dup
      content.sub!(/(\d+)(e)/, '\1<sup>\2</sup>') if language == "fr"
      Relaton::Bib::Title.new(content: content, language: language, script: "Latn")
    end

    def date(at)
      at = at.to_s
      return [] if at.empty?

      [Relaton::Bib::Date.new(type: "published", at: at)]
    end

    # en: "JCGM 17th Meeting (2012)"; fr: "JCGM 17<sup>e</sup> réunion (2012)";
    # plus the combined "en / fr" form (mirrors BIPM's create_meeting_docids).
    def docids(en_id)
      fr_id = en_id.sub(/(\d+)(?:st|nd|rd|th)/, '\1e').sub("Meeting", "réunion")
      fr_id_sup = fr_id.sub(/(\d+)(e)/, '\1<sup>\2</sup>')
      [
        docid(en_id, language: "en"),
        docid(fr_id_sup, language: "fr"),
        docid("#{en_id} / #{fr_id_sup}"),
      ]
    end

    def docid(content, language: nil)
      attrs = { content: content, type: "BIPM", primary: true }
      attrs.merge!(language: language, script: "Latn") if language
      Docidentifier.new(**attrs)
    end

    def links(md_en, md_fr, src, pdf)
      links = []
      links << uri("citation", md_en["url"], "en") if md_en && md_en["url"]
      links << uri("citation", md_fr["url"], "fr") if md_fr && md_fr["url"]
      Array(pdf).each { |p| links << Relaton::Bib::Uri.new(type: "pdf", content: p) }
      links + Array(src)
    end

    def uri(type, content, language)
      Relaton::Bib::Uri.new(type: type, content: content, language: language, script: "Latn")
    end

    # en/fr `src` links back to the source files in bipm-data-outcomes.
    def meeting_links(en_file, fr_file)
      { "en" => en_file, "fr" => fr_file }.filter_map do |lang, file|
        next unless file

        src = GH_SRC + file.split("/")[-3..].unshift("main").join("/")
        Relaton::Bib::Uri.new(type: "src", content: src, language: lang, script: "Latn")
      end
    end

    def ext(num)
      Ext.new(doctype: Doctype.new(content: "meeting-report"),
              structuredidentifier: StructuredIdentifier.new(docnumber: num))
    end

    def bipm_contrib
      names = [
        Relaton::Bib::TypedLocalizedString.new(content: "International Bureau of Weights and Measures", language: "en", script: "Latn"),
        Relaton::Bib::TypedLocalizedString.new(content: "Bureau international des poids et mesures", language: "fr", script: "Latn"),
      ]
      org = Relaton::Bib::Organization.new(
        name: names,
        abbreviation: Relaton::Bib::LocalizedString.new(content: "BIPM", language: "fr", script: "Latn"),
        uri: [Relaton::Bib::Uri.new(content: "www.bipm.org")],
      )
      Relaton::Bib::Contributor.new(
        organization: org,
        role: [Relaton::Bib::Contributor::Role.new(type: "publisher")],
      )
    end
  end
end
