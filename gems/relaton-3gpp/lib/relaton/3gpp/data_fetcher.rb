require "fileutils"
require "net/http"
require "uri"
require_relative "../3gpp"
require_relative "parser"

module Relaton
  module ThreeGpp
    class DataFetcher < Core::DataFetcher
      CURRENT = "current.yaml".freeze
      CSV_URL = "https://www.3gpp.org/ftp/Information/Databases/3GPPBibliography.csv".freeze

      def log_error(msg)
        Util.error msg
      end

      def index
        @index ||= Relaton::Index.find_or_create "3gpp", file: "#{INDEXFILE}.yaml"
      end

      #
      # Parse documents
      #
      # @param [String] source source of documents, status-smg-3gpp for updare
      #   or status-smg-3gpp-force for renewal
      #
      def fetch(source) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        renewal = source == "status-smg-3GPP-force"
        file = get_file renewal
        return unless file && File.exist?(file) && File.size(file) > 20_000_000

        if renewal
          FileUtils.rm_f Dir.glob(File.join(@output, "/*"))
          index.remove_all # if renewal
        end
        CSV.open(file, "r:bom|utf-8", headers: true, col_sep: ";").each do |row|
          save_doc Parser.parse(row, @errors)
        end
        File.write CURRENT, @current.to_yaml, encoding: "UTF-8"
        index.save
        report_errors
      end

      #
      # Get file via HTTPS. If file has not changed, return nil
      #
      # @param [Boolean] renewal force to update all documents
      #
      # @return [String, nil] file name
      #
      def get_file(renewal) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        @current = YAML.load_file CURRENT if File.exist? CURRENT
        @current ||= {}
        uri = URI(CSV_URL)
        n = 0
        begin
          last_modified = head_last_modified(uri)
          return unless last_modified

          dt = DateTime.parse(last_modified)
          if !renewal && !@current["date"].to_s.empty? &&
              dt == DateTime.parse(@current["date"])
            return
          end

          tmp_file = File.join Dir.tmpdir, "3gpp.csv"
          download(uri, tmp_file)
        rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => e
          n += 1
          retry if n < 5
          raise e
        end
        @current["date"] = dt.to_s
        tmp_file
      end

      def head_last_modified(uri)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: 30, read_timeout: 30) do |http|
          resp = http.request(Net::HTTP::Head.new(uri.request_uri))
          raise "HTTP #{resp.code} from #{uri}" unless resp.is_a?(Net::HTTPSuccess)

          resp["last-modified"]
        end
      end

      def download(uri, tmp_file)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: 30, read_timeout: 120) do |http|
          http.request(Net::HTTP::Get.new(uri.request_uri)) do |resp|
            raise "HTTP #{resp.code} from #{uri}" unless resp.is_a?(Net::HTTPSuccess)

            File.open(tmp_file, "wb") { |f| resp.read_body { |chunk| f.write(chunk) } }
          end
        end
      end

      #
      # Save document to file
      #
      # @param [RelatonW3c::W3cBibliographicItem, nil] bib bibliographic item
      #
      def save_doc(bib) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
        return unless bib

        bib1 = bib
        file = output_file(bib1.docnumber)
        if @files.include? file
          bib1 = merge_duplication bib1, file
          Util.warn "File #{file} already exists. Document: #{bib.docnumber}" if bib1.nil?
        else
          @files << file
          index.add_or_update bib1.docnumber, file
        end
        File.write file, serialize(bib1), encoding: "UTF-8" unless bib1.nil?
      end

      #
      # Merge duplication
      #
      # @param [Relaton3gpp::BibliographicItem] bib new bibliographic item
      # @param [String] file file name of existing bibliographic item
      #
      # @return [Relaton3gpp::BibliographicItem, nil] merged bibliographic item or nil if no merge has been done
      #
      def merge_duplication(bib, file)
        hash = YAML.load_file file
        existed = Item.from_hash hash
        changed = update_source? bib, existed
        bib1, bib2, chng = transposed_relation bib, existed
        changed ||= chng
        chng = add_contributor(bib1, bib2)
        changed ||= chng
        bib1 if changed
      end

      #
      # Update link in case one of bibliographic items has no link
      #
      # @param [Relaton3gpp::BibliographicItem] bib1
      # @param [Relaton3gpp::BibliographicItem] bib2
      #
      # @return [Boolean] true if link has been updated
      #
      def update_source?(bib1, bib2)
        if bib1.source.any? && bib2.source.empty?
          bib2.source = bib1.source
          true
        elsif bib1.source.empty? && bib2.source.any?
          bib1.source = bib2.source
          true
        else false
        end
      end

      #
      # If one of bibliographic items has date gereater than anotherm=, make it relation
      #
      # @param [Relaton3gpp::BibliographicItem] bib new bibliographic item
      # @param [Relaton3gpp::BibliographicItem] existed existing bibliographic item
      #
      # @return [Array<Relaton3gpp::BibliographicItem, Boolean>] main bibliographic item,
      #   related bibliographic item, true if relation has been added
      #
      def transposed_relation(bib, existed) # rubocop:disable Metrics/CyclomaticComplexity
        if (bib.date.none? && existed.date.none?) || (bib.date.any? && existed.date.none?)
          return [bib, existed, false]
        end
        return [existed, bib, true] if bib.date.none? && existed.date.any?

        check_transposed_date bib, existed
      end

      #
      # Check if date of one bibliographic item is transposed to another
      #
      # @param [Relaton3gpp::BibliographicItem] bib new bibliographic item
      # @param [Relaton3gpp::BibliographicItem] existed existing bibliographic item
      #
      # @return [Array<Relaton3gpp::BibliographicItem, Boolean>] main bibliographic item,
      #   related bibliographic item, true if relation has been added
      #
      def check_transposed_date(bib, existed)
        if bib.date[0].at < existed.date[0].at
          add_transposed_relation bib, existed
          [bib, existed, true]
        elsif bib.date[0].at > existed.date[0].at
          add_transposed_relation existed, bib
          [existed, bib, true]
        else [bib, existed, false]
        end
      end

      #
      # Add transposed relation
      #
      # @param [Relaton3gpp::BibliographicItem] bib1 the main bibliographic item
      # @param [Relaton3gpp::BibliographicItem] bib2 the transposed bibliographic item
      #
      # @return [Relaton3gpp::BibliographicItem]
      #
      def add_transposed_relation(bib1, bib2)
        bib2.relation.each { |r| bib1.relation << r }
        bib2.relation.clear
        desc = Bib::LocalizedMarkedUpString.new content: "equivalent"
        rel = Bib::Relation.new(type: "adoptedAs", bibitem: bib2, description: desc)
        bib1.relation << rel
      end

      def add_contributor(bib1, bib2) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        changed = false

        bib2.contributor.each do |bc|
          next unless bc.person

          existed = bib1.contributor.find { |ic| ic.person&.name == bc.person.name }
          if existed
            chng = add_affiliation existed, bc.person.affiliation
            changed ||= chng
          else
            bib1.contributor << bc
            changed = true
          end
        end

        changed
      end

      def add_affiliation(contrib, affiliation)
        changed = false

        affiliation.each do |a|
          unless contrib.person.affiliation.include? a
            contrib.person.affiliation << a
            changed = true
          end
        end

        changed
      end

      def to_xml(bib)
        bib.to_xml(bibdata: true)
      end

      def to_yaml(bib)
        bib.to_yaml
      end

      def to_bibxml(bib)
        bib.to_rfcxml
      end
    end
  end
end
