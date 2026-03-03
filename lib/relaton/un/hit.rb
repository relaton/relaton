# frozen_string_literal: true

module Relaton
  module Un
    class Hit < Core::Hit
      # rubocop:disable Layout/LineLength

      DISTRIBUTIONS = { "GEN" => "general", "LTD" => "limited",
                        "DER" => "restricted", "PRO" => "provisional" }.freeze

      BODY = {
        "A" => "General Assembly",
        "E" => "Economic and Social Council",
        "S" => "Security Council",
        "T" => "Trusteeship Council",
        "ACC" => "Administrative Committee on Coordination",
        "AT" => "United Nations Administrative Tribunal",
        "CAT" => "Committee against Torture",
        "CCPR" => "Human Rights Committee",
        "CD" => "Conference on Disarmament",
        "CEDAW" => "Committee on the Elimination of All Forms of Discrimination against Women",
        "CERD" => "Committee on the Elimination of Racial Discrimination",
        "CRC" => "Committee on the Rights of the Child",
        "DC" => "Disarmament Commission",
        "DP" => "United Nations Development Programme",
        "HS" => "United Nations Centre for Human Settlements (HABITAT)",
        "TD" => "United Nations Conference on Trade and Development",
        "UNEP" => "United Nations Environment Programme",
        "TRADE" => "Committee on Trade",
        "CEFACT" => "Centre for Trade Facilitation and Electronic Business",
        "C.1" => "Disarmament and International Security Committee",
        "C.2" => "Economic and Financial Committee",
        "C.3" => "Social, Humanitarian & Cultural Issues",
        "C.4" => "Special Political and Decolonization Committee",
        "C.5" => "Administrative and Budgetary Committee",
        "C.6" => "Sixth Committee (Legal)",
        "PC" => "Preparatory Committee",
        "AEC" => "Atomic Energy Commission",
        "AGRI" => "Committee on Agriculture",
        "AMCEN" => "African Ministerial Conference on the Environment",
        "AMCOW" => "African Ministers' Council on Water",
        "ECA" => "Economic Commission for Africa",
        "ESCAP" => "Economic and Social Commission for Asia and Pacific",
        "ECE" => "Economic Commission for Europe",
        "ECWA" => "Economic Commission for Western Asia",
        "UNFF" => "United Nations Forum on Forests",
        "ENERGY" => "Committee on Sustainable Energy",
        "FAO" => "Food and Agriculture Organization",
        "UNCTAD" => "United Nations Conference on Trade and Development",
      }.freeze
      # rubocop:enable Layout/LineLength

      # Parse page.
      # @return [Relaton::Un::Item]
      def item
        @item ||= un_bib_item
      end

      private

      # rubocop:disable Metrics/MethodLength

      # @return [Relaton::Un::Item]
      def un_bib_item # rubocop:disable Metrics/AbcSize
        Item.new(
          type: "standard",
          fetched: Date.today.to_s,
          docidentifier: fetch_docid,
          docnumber: hit["symbol"],
          language: ["en"],
          script: ["Latn"],
          title: fetch_title,
          date: fetch_date,
          source: fetch_link,
          keyword: fetch_keyword,
          ext: Ext.new(
            session: fetch_session,
            distribution: fetch_distribution,
            job_number: fetch_job_number,
          ),
        )
      end
      # rubocop:enable Metrics/MethodLength

      # @return [Array<Relaton::Bib::Docidentifier>]
      def fetch_docid
        symbols = hit["symbols"]&.compact&.reject(&:empty?) || []
        dids = symbols.map { |s| Bib::Docidentifier.new(content: s, type: "UN") }
        dids.first.primary = true unless dids.empty?
        dids
      end

      # @return [Array<Relaton::Bib::Title>]
      def fetch_title
        title = english_data&.dig("title") || ""
        Bib::Title.from_string title, "en", "Latn"
      end

      # @return [Array<Relaton::Bib::Date>]
      def fetch_date
        d = []
        if (pub = hit["publication_date"])
          d << Bib::Date.new(type: "published", at: pub[0, 10])
        end
        if (rel = english_data&.dig("release_date"))
          d << Bib::Date.new(type: "issued", at: rel[0, 10])
        end
        d
      end

      # @return [Array<Relaton::Bib::Uri>]
      def fetch_link
        jn = fetch_job_number
        return [] unless jn && !jn.empty?

        [Bib::Uri.new(
          content: "https://documents.un.org/api/symbol/access?j=#{jn}&t=pdf",
          type: "pdf",
        )]
      end

      # @return [Array<Relaton::Bib::Keyword>]
      def fetch_keyword
        subjects = english_data&.dig("subjects") || []
        subjects.map do |kw|
          Bib::Keyword.new(vocab: [Bib::LocalizedString.new(content: kw)])
        end
      end

      # @return [Relaton::Un::Session]
      def fetch_session
        session_num = hit["sessions"]&.compact&.reject(&:empty?)&.first
        agenda = hit["agendas"]&.compact&.reject(&:empty?)&.first
        Session.new(number: session_num, agenda_id: agenda)
      end

      # @return [String, nil]
      def fetch_distribution
        DISTRIBUTIONS[hit["distribution"]]
      end

      # @return [String, nil]
      def fetch_job_number
        en = english_data
        jn = en&.dig("job_number")
        return jn if jn && !jn.empty?

        hit["job_numbers"]&.compact&.reject(&:empty?)&.first
      end

      # @return [Hash, nil] the English perLanguage entry
      def english_data
        @english_data ||= hit["perLanguage"]&.find { |pl| pl["language"] == "English" }
      end
    end
  end
end
