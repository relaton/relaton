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
      case stdclass
      when :isobib then Isobib::IsoBibliography.get(code, year, opts)
      else
        nil
      end
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
            "#{code} does not have a recognised prefix: #{PREFIXES.join(', ')}"
      nil
    end

    def open_cache_biblio(filename)
      biblio = {}
      if Pathname.new(filename).file?
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
