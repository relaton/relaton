module Relaton
  class RelatonError < StandardError; end

  class Db
    PREFIXES = ["GB Standard", "IETF", "ISO", "IEC", "IEV"]

    def initialize(global_cache, local_cache)
      @bibdb = open_cache_biblio(global_cache)
      @local_bibdb = open_cache_biblio(local_cache)
      @bibdb_name = global_cache
      @local_bibdb_name = local_cache
    end

    # The class of reference requested is determined by the prefix of the code:
    # GB Standard for gbbib, IETF for rfcbib, ISO or IEC or IEV for isobib
    # @param code [String] the ISO standard Code to look up (e..g "ISO 9000")
    # @param year [String] the year the standard was published (optional)
    # @param opts [Hash] options; restricted to :all_parts if all-parts reference is required
    # @return [String] Relaton XML serialisation of reference
    def get(code, year, opts)
      stdclass = standard_class(code)
      check_bibliocache(code, year, opts, stdclass)
    end

    def save()
      save_cache_biblio(@bibdb, @bibdb_name)
      save_cache_biblio(@local_bibdb, @local_bibdb_name)
    end

    private

    def standard_class(code)
      %r{^GB Standard }.match? code and return :gbbib
      %r{^IETF }.match? code and return :rfcbib
      %r{^(ISO|IEC)[ /]|IEV($| )}.match? code and return :isobib
      raise(RelatonError, 
            "#{code} does not have a recognised prefix: #{PREFIXES.join(', ')}")
      nil
    end

    def std_id(code, year, opts, _stdclass)
      ret = code
      ret += ":#{year}" if year
      ret += " (all parts)" if opts[:all_parts]
      ret
    end

    def check_bibliocache(code, year, opts, stdclass)
      id = std_id(code, year, opts, stdclass)
      return nil if @bibdb.nil? # signals we will not be using isobib
      @bibdb[id] = nil unless is_valid_bibcache_entry?(@bibdb[id], year)
      @bibdb[id] ||= new_bibcache_entry(code, year, opts, stdclass)
      @local_bibdb[id] = @bibdb[id] if !@local_bibdb.nil? &&
        !is_valid_bibcache_entry?(@local_bibdb[id], year)
      return @local_bibdb[id]["bib"] unless @local_bibdb.nil?
      @bibdb[id]["bib"]
    end

    # hash uses => , because the hash is imported from JSON
    def new_bibcache_entry(code, year, opts, stdclass)
      bib = case stdclass
            when :isobib then Isobib::IsoBibliography.get(code, year, opts)
            else
              nil
            end
      return nil if bib.nil?
      { "fetched" => Date.today, "bib" => bib }
    end

    # if cached reference is undated, expire it after 60 days
    def is_valid_bibcache_entry?(x, year)
      x && x.is_a?(Hash) && x&.has_key?("bib") && x&.has_key?("fetched") &&
        (year || Date.today - Date.iso8601(x["fetched"]) < 60)
    end

    def open_cache_biblio(filename)
      biblio = {}
      if !filename.nil? && Pathname.new(filename).file?
        File.open(filename, "r") do |f|
          biblio = JSON.parse(f.read)
        end
      end
      biblio
    end

    def save_cache_biblio(biblio, filename)
      return if biblio.nil?
      File.open(filename, "w") do |b|
        b << biblio.to_json
      end
    end
  end
end
