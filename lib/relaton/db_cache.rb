require "fileutils"
require "timeout"
require "relaton/storage"

module Relaton
  class DbCache
    # @return [String]
    attr_reader :dir

    # @param dir [String] DB directory
    def initialize(dir, ext = "xml")
      @dir = dir
      @ext = ext
      @storage = Storage.instance
      FileUtils::mkdir_p @dir unless Relaton.configuration.api_mode
    end

    # Move caches to anothe dir
    # @param new_dir [String, nil]
    # @return [String, nil]
    def mv(new_dir)
      return unless new_dir && @ext == "xml" && !Relaton.configuration.api_mode

      if File.exist? new_dir
        warn "[relaton] WARNING: target directory exists \"#{new_dir}\""
        return
      end

      FileUtils.mv dir, new_dir
      @dir = new_dir
    end

    # Clear database
    def clear
      return if Relaton.configuration.api_mode

      FileUtils.rm_rf Dir.glob "#{dir}/*" if @ext == "xml" # if it's static DB
    end

    # Save item
    # @param key [String]
    # @param value [String] Bibitem xml serialization
    def []=(key, value)
      if value.nil?
        delete key
        return
      end
      /^(?<pref>[^(]+)(?=\()/ =~ key.downcase
      prefix_dir = "#{@dir}/#{pref}"
      file = "#{filename(key)}.#{ext(value)}"
      @storage.save prefix_dir, file, value
    end

    # Read item
    # @param key [String]
    # @return [String]
    def [](key)
      value = get(key)
      if (code = redirect? value)
        self[code]
      else
        value
      end
    end

    def clone_entry(key, db)
      self[key] ||= db.get(key)
      if (code = redirect? get(key))
        clone_entry code, db
      end
    end

    # Return fetched date
    # @param key [String]
    # @return [String]
    def fetched(key)
      value = self[key]
      return unless value

      if value.match?(/^not_found/)
        value.match(/\d{4}-\d{2}-\d{2}/).to_s
      else
        doc = Nokogiri::XML value
        doc.at("/bibitem/fetched|bibdata/fetched")&.text
      end
    end

    # Returns all items
    # @return [Array<String>]
    def all(&block)
      @storage.all(@dir, &block)
    end

    # Delete item
    # @param key [String]
    def delete(key)
      @storage.delete filename(key)
    end

    # Check if version of the DB match to the gem grammar hash.
    # @param fdir [String] dir pathe to flover cache
    # @return [Boolean]
    def check_version?(fdir)
      @storage.check_version? fdir
    end

    # if cached reference is undated, expire it after 60 days
    # @param key [String]
    # @param year [String]
    def valid_entry?(key, year)
      datestr = fetched key
      return false unless datestr

      date = Date.parse datestr
      year || Date.today - date < 60
    end

    # Reads file by a key
    #
    # @param key [String]
    # @return [String, NilClass]
    def get(key)
      @storage.get filename(key)
    end

    private

    # @param value [String]
    # @return [String]
    def ext(value)
      case value
      when /^not_found/ then "notfound"
      when /^redirection/ then "redirect"
      else @ext
      end
    end

    # Return item's file name
    # @param key [String]
    # @return [String]
    def filename(key)
      prefcode = key.downcase.match(/^(?<prefix>[^(]+)\((?<code>[^)]+)/)
      fn = if prefcode
             "#{prefcode[:prefix]}/#{prefcode[:code].gsub(/[-:\s\/()]/, '_')
               .squeeze('_')}"
           else
             key.gsub(/[-:\s]/, "_")
           end
      "#{@dir}/#{fn.sub(/(,|_$)/, '')}"
    end

    # Check if a file content is redirection
    #
    # @prarm value [String] file content
    # @return [String, NilClass] redirection code or nil
    def redirect?(value)
      %r{redirection\s(?<code>.*)} =~ value
      code
    end

    # Return item's subdir
    # @param key [String]
    # @return [String]
    # def prefix(key)
    #   key.downcase.match(/^[^(]+(?=\()/).to_s
    # end
  end
end
