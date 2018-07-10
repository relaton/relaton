require_relative "registry"

module Relaton
  class RelatonError < StandardError; end

  class Db
    SUPPORTED_GEMS = %w[ isobib rfcbib gbbib ].freeze

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

    def save
      save_cache_biblio(@db, @db_name)
      save_cache_biblio(@local_db, @local_db_name)
    end

    private

    def standard_class(code)
=begin
      %r{^GB Standard }.match? code and return :gbbib
      %r{^IETF }.match? code and return :rfcbib
      %r{^(ISO|IEC)[ /]|IEV($| )}.match? code and return :isobib
=end
      @registry.processors.each do |name, processor|
        processor.prefix.match? code and return name
      end
      allowed = @registry.processors.inject([]) do |m, (k, v)|
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
      ret
    end

    def check_bibliocache(code, year, opts, stdclass)
      id = std_id(code, year, opts, stdclass)
      return nil if @db.nil? # signals we will not be using isobib
      @db[id] = nil unless is_valid_bib_entry?(@db[id], year)
      @db[id] ||= new_bib_entry(code, year, opts, stdclass)
      if !@local_db.nil?
        @local_db[id] = @db[id] if !is_valid_bib_entry?(@local_db[id], year)
        return nil if @local_db[id]["bib"] == :not_found
        return @local_db[id]["bib"]
      end
      @db[id]["bib"] == :not_found ? nil : @db[id]["bib"]
    end

    # hash uses => , because the hash is imported from JSON
    def new_bib_entry(code, year, opts, stdclass)
      bib = @registry.processors[stdclass].get(code, year, opts)
      bib = :not_found if bib.nil?
      { "fetched" => Date.today, "bib" => bib }
    end

    # if cached reference is undated, expire it after 60 days
    def is_valid_bib_entry?(x, year)
      x && x.is_a?(Hash) && x&.has_key?("bib") && x&.has_key?("fetched") &&
        (year || Date.today - Date.iso8601(x["fetched"]) < 60)
    end

    def open_cache_biblio(filename)
      biblio = {}
      return {} unless !filename.nil? && Pathname.new(filename).file?
      File.open(filename, "r") { |f| biblio = JSON.parse(f.read) }
      biblio.each do |k, v|
        biblio[k]&.fetch("bib") and
          biblio[k]["bib"] = from_xml(biblio[k]["bib"])
      end
      biblio
    end

    def from_xml(entry)
      entry # will be unmarshaller
    end

    def save_cache_biblio(biblio, filename)
      return if biblio.nil? || filename.nil?
      biblio.each do |k, v|
        biblio[k]&.fetch("bib")&.respond_to? :to_xml and
          biblio[k]["bib"] = biblio[k]["bib"].to_xml
      end
      File.open(filename, "w") do |b|
        b << biblio.to_json
      end
    end
  end
end
