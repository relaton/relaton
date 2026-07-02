module Relaton
  module Itu
    class RecommendationParser
      include Relaton::Core::ArrayWrapper

      RECHDR = "https://www.itu.int/mws/api/recommendations/getRecHdrDetail?idrec=%{idrec}&lang=en"
      RECEDITIONS = "https://www.itu.int/mws/api/recommendations/getRecEditions?idrec=%{idrec}&lang=en"
      RECSUPPLEMENTS = "https://www.itu.int/mws/api/recommendations/getRecSupplements?idrec=%{idrec}&lang=en"
      IMPLGUIDES = "https://www.itu.int/mws/api/recommendations/getImplGuides?idrec=%{idrec}&lang=en"

      def initialize(hit, idrec, imp)
        @hit = hit
        @idrec = idrec
        @imp = imp
      end

      def doc
        @doc ||= begin
          url = (imp ? IMPLGUIDES : RECHDR) % { idrec: idrec }
          resp = get_data url
          imp ? resp.first : resp
        end
      end

      # @return [String, nil]
      def fetch_edition
        self_edition&.dig("Version")
      end

      # @return [Array<Relaton::Bib::Title>]
      def fetch_titles
        title = imp ? doc["imp_title_e"] : doc["rec_title"]
        return [] if title.nil? || title.empty?

        Relaton::Bib::Title.from_string title, "en", "Latn"
      end

      # @return [Relaton::Bib::Status, nil]
      def fetch_status
        inforce = imp ? imp_status : doc["status"]
        return if inforce.nil? || inforce.empty?

        status = inforce == "In force" ? "Published" : "Withdrawal"
        Relaton::Bib::Status.new(stage: Relaton::Bib::Status::Stage.new(content: status))
      end

      # @return [Array<Relaton::Bib::Date>]
      def fetch_dates
        array(doc_date).map { |on| Relaton::Bib::Date.new(type: "published", at: on) }
      end

      # @return [Array<Relaton::Bib::LocalizedMarkedUpString>]
      def fetch_abstract
        array(doc["summary"]).map do |content|
          Relaton::Bib::Abstract.new(content: content, language: "en", script: "Latn")
        end
      end

      # @return [Array<Relaton::Bib::Uri>]
      def fetch_source
        link = imp ? doc["imp_dms_link"] : doc["handle_id"]
        links = [Relaton::Bib::Uri.new(type: "src", content: link)]
        links << Relaton::Bib::Uri.new(type: "pdf", content: doc["handle_id_pdf_link"]) if doc["handle_id_pdf_link"]
        imp_word_link { |wlink| links << Relaton::Bib::Uri.new(type: "word", content: wlink) }
        links
      end

      def doc_date
        return @doc_date if defined? @doc_date

        date = imp ? doc["imp_approval_date"] : doc["approval_date"]
        @doc_date = Date.parse(date).to_s rescue date # rubocop:disable Style/RescueModifier
      end

      # @return [Array<Relaton::Bib::Relation>]
      def fetch_relations
        relations = []
        editions.each do |ed|
          next if ed["idrec"] == idrec

          relations << create_relation("hasEdition", ed["title"], ed["rec_name"])
        end

        supplements.each { |supp| relations << create_relation("complementOf", supp["title_text"], supp["rec_name"]) }
        relations
      end

        # Fetch the study group name from the recommendation HTML page.
      # @return [String, nil]
      def fetch_workgroup
        url = "https://www.itu.int/ITU-T/recommendations/rec.aspx?rec=#{idrec}&lang=en"
        page = hit.hit_collection.agent.get(url)
        wg = page.at('//span[contains(@id, "uc_rec_main_info1_rpt_main_ctl00_Label8")]/a')
        wg&.text
      rescue StandardError
        nil
      end

      private

      attr_reader :hit, :idrec, :imp

      def get_data(url)
        JSON.parse request_document(url).body
      end

      def request_document(url)
        hit.hit_collection.agent.get url
      rescue Mechanize::ResponseCodeError, SocketError, Timeout::Error, Errno::ECONNRESET,
              EOFError, Net::ProtocolError, OpenSSL::SSL::SSLError => e
        raise Relaton::RequestError, "Could not access #{url}: #{e.message}"
      end

      def editions
        @editions ||= begin
          url = RECEDITIONS % { idrec: idrec }
          get_data(url) || []
        end
      end

      def self_edition
        @self_edition ||= editions.find { |ed| ed["idrec"] == idrec }
      end

      def imp_status
        self_edition&.dig("status")
      end

      def imp_word_link
        return unless doc["imp_dms_link"]

        @doc_page ||= request_document(doc["imp_dms_link"])
        wrd_elm = @doc_page.at("//font[contains(.,'Word')]/../..")
        yield wrd_elm[:href] if block_given? && wrd_elm
      end

      def create_relation(type, title_text, id)
        titles = []
        if title_text && !title_text.empty?
          titles << Relaton::Bib::Title.new(content: title_text, language: "en", script: "Latn")
        end

        fref = titles.empty? ? id : nil
        did = Relaton::Bib::Docidentifier.new(type: "ITU", content: id, primary: true)
        bibitem = Relaton::Bib::ItemData.new(title: titles, formattedref: (fref ? Relaton::Bib::Formattedref.new(content: fref) : nil), docidentifier: [did])
        Relaton::Bib::Relation.new(type: type, bibitem: bibitem)
      end

      def supplements
        @supplements ||= begin
          if imp
            []
          else
            url = RECSUPPLEMENTS % { idrec: idrec }
            get_data(url) || []
          end
        end
      end
    end
  end
end
