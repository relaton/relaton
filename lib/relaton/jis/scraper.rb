# encoding: UTF-8
# frozen_string_literal: true

module Relaton
  module Jis
    class Scraper
      ATTRS = %i[
        title source abstract docidentifier docnumber date type language script
        status contributor structuredidentifier ext
      ].freeze

      LANGS = { "和文" => { lang: "ja", script: "Jpan" },
                "英訳" => { lang: "en", script: "Latn" } }.freeze

      DATETYPES = { "発行年月日" => "issued", "確認年月日" => "confirmed" }.freeze
      STATUSES = { "有効" => "valid", "廃止" => "withdrawn" }.freeze

      def initialize(url)
        @url = url
        @agent = Mechanize.new
      end

      def fetch # rubocop:disable Metrics/MethodLength
        @doc = @agent.get(@url).at "//div[@id='main']/section"
        contributors = fetch_contributor
        eg_contributor = fetch_editorialgroup_contributor
        contributors << eg_contributor if eg_contributor
        attrs = ATTRS.each_with_object({}) do |attr, hash|
          hash[attr] = send "fetch_#{attr}"
        end
        attrs[:contributor] = contributors
        Bib::ItemData.new(**attrs)
      end

      def fetch_title
        { "ja" => "Jpan", "en" => "Latn" }.map.with_index do |(lang, script), i|
          content = @doc.at("./h2/text()[#{i + 2}]").text.strip
          Bib::Title.new content: content, language: lang, script: script
        end
      end

      def fetch_source # rubocop:disable Metrics/MethodLength
        src = Bib::Uri.new content: @url, type: "src"
        uri = URI @url
        domain = "#{uri.scheme}://#{uri.host}"
        xpath = "./dl/dt[.='プレビュー']/following-sibling::dd[1]/a"
        @doc.xpath(xpath).reduce([src]) do |mem, node|
          href = "#{domain}#{node[:href]}"
          mem << Bib::Uri.new(content: href, type: "pdf")
        end
      end

      def fetch_abstract
        @doc.xpath("//div[@id='honbun']").map do |node|
          Bib::LocalizedMarkedUpString.new(
            content: node.text.strip,
            language: "ja", script: "Jpan"
          )
        end
      end

      def fetch_docidentifier
        docid = document_id
        [Docidentifier.new(
          content: docid, type: "JIS", primary: true,
        )]
      end

      def fetch_docnumber
        match = document_id.match(/^\w+\s(\w)\s?(\d+)/)
        "#{match[1]}#{match[2]}"
      end

      def document_id
        @document_id ||= @doc.at("./h2/text()[1]").text.strip
      end

      def fetch_date
        DATETYPES.each_with_object([]) do |(key, type), a|
          node = @doc.at("./div/div/div/p/text()[contains(.,'#{key}')]")
          next unless node

          at = node.text.match(/\d{4}-\d{2}-\d{2}/).to_s
          a << Bib::Date.new(type: type, at: at)
        end
      end

      def fetch_type
        "standard"
      end

      def fetch_language
        langs_scripts.map { |l| l[:lang] }
      end

      def fetch_script
        langs_scripts.map { |l| l[:script] }
      end

      def langs_scripts
        @langs_scripts ||= LANGS.each_with_object([]) do |(key, lang), a|
          l = @doc.at(
            "./div/div/div[@class='blockContentFile']/div/div/p[1]" \
            "/span[contains(.,'#{key}')]/following-sibling::span",
          )
          next if l.nil? || l.text.strip == "-"

          a << lang
        end
      end

      def fetch_status
        xpath = "./div/div/div/p/text()[contains(.,'状態')]" \
                "/following-sibling::span"
        st = @doc.at(xpath)
        return unless st

        stage = Bib::Status::Stage.new(content: STATUSES[st.text.strip])
        Bib::Status.new(stage: stage)
      end

      def fetch_doctype
        type = case document_id
               when /JIS\s[A-Z]\s[\w-]+:\d{4}\/AMENDMENT/ then "amendment"
               when /JIS\s[A-Z]\s[\w-]+/ then "japanese-industrial-standard"
               when /TR[\s\/][\w-]+/ then "technical-report"
               when /TS[\s\/][\w-]+/ then "technical-specification"
               end
        Doctype.new content: type
      end

      def fetch_ics
        td = @doc.at("./table/tr[th[.='ICS']]/td")
        return [] unless td

        td.text.strip.split.map { |code| Bib::ICS.new code: code }
      end

      def fetch_contributor
        authorizer = create_contrib(
          "一般財団法人　日本規格協会", "authorizer"
        )
        xpath = "./table/tr[th[.='原案作成団体']]/td"
        @doc.xpath(xpath).reduce([authorizer]) do |a, node|
          a << create_contrib(node.text.strip, "author")
          a << create_contrib(node.text.strip, "publisher")
        end
      end

      def create_contrib(name, role)
        org = Bib::Organization.new name: create_orgname(name)
        role_obj = Bib::Contributor::Role.new(type: role)
        Bib::Contributor.new organization: org, role: [role_obj]
      end

      def create_orgname(name)
        tls = Bib::TypedLocalizedString
        orgname = [tls.new(content: name, language: "ja", script: "Jpan")]
        if name.include?("日本規格協会")
          orgname << tls.new(
            content: "Japanese Industrial Standards",
            language: "en", script: "Latn"
          )
        end
        orgname
      end

      def fetch_editorialgroup_contributor # rubocop:disable Metrics/MethodLength
        node = @doc.at("./table/tr[th[.='原案作成団体']]/td")
        return unless node

        subdivision = Bib::Subdivision.new(
          type: "technical-committee",
          name: [Bib::TypedLocalizedString.new(content: node.text.strip)],
        )
        desc = Bib::LocalizedMarkedUpString.new(content: "committee")
        role = Bib::Contributor::Role.new(
          type: "author", description: [desc],
        )
        org = Bib::Organization.new(
          name: [], subdivision: [subdivision],
        )
        Bib::Contributor.new(role: [role], organization: org)
      end

      def fetch_structuredidentifier
        Iso::StructuredIdentifier.new(
          project_number: Iso::ProjectNumber.new(content: fetch_docnumber),
          type: "JIS",
        )
      end

      def fetch_ext
        Ext.new(
          doctype: fetch_doctype,
          flavor: "jis",
          ics: fetch_ics,
          structuredidentifier: fetch_structuredidentifier,
        )
      end
    end
  end
end
