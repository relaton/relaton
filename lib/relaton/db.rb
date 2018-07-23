require "pstore"
require_relative "registry"

module Relaton
  class RelatonError < StandardError; end

  class Db
    SUPPORTED_GEMS = %w[isobib rfcbib gbbib].freeze

    # @param global_cache [String] filename of global DB
    # @param local_cache [String] filename of local DB
    def initialize(global_cache, local_cache)
      @db = open_cache_biblio(global_cache)
      @local_db = open_cache_biblio(local_cache)
      @db_name = global_cache
      @local_db_name = local_cache
      register_gems
      @registry = Relaton::Registry.instance
    end

    def register_gems
      puts "[relaton] detecting backends:"
      SUPPORTED_GEMS.each do |b|
        puts b
        begin
          require b
        rescue LoadError
          puts "[relaton] backend #{b} not present"
        end
      end
    end

    # The class of reference requested is determined by the prefix of the code:
    # GB Standard for gbbib, IETF for rfcbib, ISO or IEC or IEV for isobib
    # @param code [String] the ISO standard Code to look up (e..g "ISO 9000")
    # @param year [String] the year the standard was published (optional)
    # @param opts [Hash] options; restricted to :all_parts if all-parts reference is required
    # @return [String] Relaton XML serialisation of reference
    def fetch(code, year = nil, opts = {})
      stdclass = standard_class(code) or return nil
      check_bibliocache(code, year, opts, stdclass)
    end

    # @param key [String]
    # @return [Hash]
    def load_entry(key)
      unless @local_db.nil?
        entry = @local_db.transaction { @local_db[key] }
        return entry if entry
      end
      @db.transaction { @db[key] }
    end

    # @param key [String]
    # @param value [Hash]
    # @option value [Date] "fetched"
    # @option value [IsoBibItem::IsoBibliographicItem] "bib"
    def save_entry(key, value)
      @db.nil? or @db.transaction { @db[key] = value }
      @local_db.nil? or @local_db.transaction { @local_db[key] = value }
    end

    # list all entris as a serialization
    def to_xml
      return nil if @db.nil?
      @db.transaction do
        Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml.documents do
            @db.roots.each { |key| @db[key]&.fetch("bib")&.to_xml(xml, {}) }
          end
        end.to_xml
      end
    end

    # def save
    #   save_cache_biblio(@db, @db_name)
    #   save_cache_biblio(@local_db, @local_db_name)
    # end

    private

    def standard_class(code)
      @registry.processors.each do |name, processor|
        processor.prefix.match?(code) and return name
      end
      allowed = @registry.processors.reduce([]) do |m, (_k, v)|
        m << v.prefix.inspect
      end
      warn "#{code} does not have a recognised prefix: #{allowed.join(', ')}"
      nil
    end

    # TODO: i18n
    def std_id(code, year, opts, _stdclass)
      ret = code
      ret += ":#{year}" if year
      ret += " (all parts)" if opts[:all_parts]
      code = code.sub(/^(GB Standard|IETF( Standard)?) /, "")
      [ret, code]
    end

    def bib_retval(entry)
      entry["bib"] == "not_found" ? nil : entry["bib"]
    end

    # @param code [String]
    # @param year [String]
    # @param opts [Hash]
    # @param stdclass [Symbol]
    def check_bibliocache(code, year, opts, stdclass)
      id, searchcode = std_id(code, year, opts, stdclass)
      return bib_retval(new_bib_entry(searchcode, year, opts, stdclass)) if @db.nil?
      @db.transaction do
        @db.delete(id) unless valid_bib_entry?(@db[id], year)
        @db[id] ||= new_bib_entry(searchcode, year, opts, stdclass)
        if @local_db.nil? then bib_retval(@db[id])
        else
          @local_db.transaction do
            @local_db[id] = @db[id] if !valid_bib_entry?(@local_db[id], year)
            bib_retval(@local_db[id])
          end
        end
      end
    end

    # hash uses => , because the hash is imported from JSONo
    # @param code [String]
    # @param year [String]
    # @param opts [Hash]
    # @param stdclass [Symbol]
    # @return [Hash]
    def new_bib_entry(code, year, opts, stdclass)
      bib = @registry.processors[stdclass].get(code, year, opts)
      bib = "not_found" if bib.nil?
      { "fetched" => Date.today, "bib" => bib }
    end

    # if cached reference is undated, expire it after 60 days
    # @param bib [Hash]
    # @param year [String]
    def valid_bib_entry?(bib, year)
      bib&.is_a?(Hash) && bib&.has_key?("bib") && bib&.has_key?("fetched") &&
        (year || Date.today - bib["fetched"] < 60)
    end

    # @param filename [String] DB filename
    # @return [Hash]
    def open_cache_biblio(filename)
      return nil if filename.nil?
      PStore.new filename
      # biblio = {}
      # return {} unless !filename.nil? && Pathname.new(filename).file?
      # File.open(filename, "r") { |f| biblio = JSON.parse(f.read) }
      # biblio.each { |_k, v| v["bib"] && (v["bib"] = from_xml(v["bib"])) }
      # biblio
    end

    # @param enstry [String] entry in XML format
    # @return [IsoBibItem::IsoBibliographicItem]
    # def from_xml(entry)
    #   IsoBibItem.from_xml entry # will be unmarshaller
    # end

    # @param [Hash{String=>Hash{String=>String}}] biblio
    # def save_cache_biblio(biblio, filename)
    #   return if biblio.nil? || filename.nil?
    #   File.open(filename, "w") do |b|
    #     b << biblio.reduce({}) do |s, (k, v)|
    #       bib = v["bib"].respond_to?(:to_xml) ? v["bib"].to_xml : v["bib"]
    #       s.merge(k => { "fetched" => v["fetched"], "bib" => bib })
    #     end.to_json
    #   end
    # end
  end
end
