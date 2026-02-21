require_relative "../itu"
require_relative "data_parser_r"

module Relaton
  module Itu
    class DataFetcher < Core::DataFetcher
      def index
        @index ||= Relaton::Index.find_or_create :itu, file: "index-v1.yaml"
      end

      # @return agent [Mechanize]
      def agent
        @agent ||= Mechanize.new
      end

      # @return workers [Relaton::Core::WorkersPool]
      def workers
        return @workers if @workers

        @workers = Relaton::Core::WorkersPool.new 10
        @workers.tap do |w|
          w.worker { |row| parse_page(*row) }
        end
      end

      # @param url [String]
      # @param type [String]
      def parse_page(url, type)
        doc = agent.get url
        bib = Relaton::Itu::DataParserR.parse doc, url, type
        write_file bib
      rescue => e # rubocop:disable Style/RescueStandardError
        Util.error "#{e.message}\n#{e.backtrace}"
      end

      def fetch(_source = nil)
        fetch_recommendation
        fetch_question
        fetch_report
        fetch_handbook
        fetch_resolution
        workers.end
        workers.result
        index.save
      end

      def fetch_recommendation
        url = "https://extranet.itu.int/brdocsearch/_layouts/15/inplview.aspx?" \
              "List=%7B0661B581-2413-4E84-BAB2-77E6DB27AF7F%7D&" \
              "View=%7BC81191DD-48C4-4881-9CB7-FB61C683FE98%7D&" \
              "ViewCount=123&" \
              "IsXslView=TRUE&" \
              "IsCSR=TRUE&" \
              "ListViewPageUrl=https%3A%2F%2Fextranet.itu.int%2Fbrdocsearch%2FR-REC%2FForms%2Ffolders_inforce.aspx&" \
              "FolderCTID=0x012001"
        json_index url, "recommendation"
      end

      def fetch_question
        url = "https://extranet.itu.int/brdocsearch/R-QUE/Forms/folders_inforce.aspx"
        html_index url, "question"
      end

      def fetch_report
        url = "https://extranet.itu.int/brdocsearch/_layouts/15/inplview.aspx?" \
              "List=%7B82E4A13D-C7F3-4844-9E8A-2463C4B7784F%7D&" \
              "View=%7B94CC1561-E4AC-4317-B402-AA0AADD7F414%7D&" \
              "ViewCount=407&" \
              "IsXslView=TRUE&" \
              "IsCSR=TRUE&" \
              "ListViewPageUrl=https%3A%2F%2Fextranet.itu.int%2Fbrdocsearch%2FR-REP%2FForms%2FFolders%2520InForce.aspx&" \
              "FolderCTID=0x012001"
        json_index url, "technical-report"
      end

      def fetch_handbook
        url = "https://extranet.itu.int/brdocsearch/R-HDB/Forms/Folders%20InForce.aspx"
        html_index url, "handbook"
      end

      def fetch_resolution
        url = "https://extranet.itu.int/brdocsearch/R-RES/Forms/Folders%20InForce.aspx"
        html_index url, "resolution"
      end

      # #param url [String]
      # @param type [String]
      def json_index(url, type) # rubocop:disable Metrics/AbcSize
        result = agent.post url
        json = JSON.parse result.body
        json["Row"].each { |row| workers << [row["serverurl.progid"].sub(/^1/, ""), type] }
        return unless json["NextHref"]

        nexturl = url.sub(/(Paged|FolderCTID)=.+/, json["NextHref"].match(/(?<=aspx\?).+/).to_s)
        json_index nexturl, type
      end

      # #param url [String]
      # @param type [String]
      def html_index(url, type)
        resp = agent.get url
        result = Nokogiri::HTML resp.body
        result.xpath("//table//table/tr[position() > 1]").each do |hit|
          url = hit.at("td/a")[:onclick].match(%r{https://[^']+}).to_s
          workers << [url, type]
        end
      end

      # @param bib [RelatonItu::ItuBibliographicItem]
      def write_file(bib) # rubocop:disable Metrics/AbcSize
        id = bib.docidentifier[0].content.gsub(/[\s.]/, "_")
        file = "#{@output}/#{id}.#{@ext}"
        if @files.include? file
          Util.warn "File #{file} exists."
        else
          @files << file
        end
        index.add_or_update bib.docidentifier[0].content, file
        File.write file, serialize(bib), encoding: "UTF-8"
      end

      def to_yaml(bib)
        bib.to_hash.to_yaml
      end

      def to_xml(bib)
        bib.to_xml bibdata: true
      end

      def to_bibxml(bib)
        bib.to_bibxml
      end
    end
  end
end
