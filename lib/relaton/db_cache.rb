require "fileutils"

module Relaton
  class DbCache
    # @return [String]
    attr_reader :dir

    # @param dir [String] DB directory
    def initialize(dir, ext = "xml")
      @dir = dir
      @ext = ext
      FileUtils::mkdir_p @dir
      # file_version = "#{@dir}/version"
      # set_version # unless File.exist? file_version
    end

    # Save item
    # @param key [String]
    # @param value [String] Bibitem xml serialization
    def []=(key, value)
      if value.nil?
        delete key
        return
      end

      prefix_dir = "#{@dir}/#{prefix(key)}"
      FileUtils::mkdir_p prefix_dir unless Dir.exist? prefix_dir
      set_version prefix_dir
      File.write "#{filename(key)}.#{ext(value)}", value, encoding: "utf-8"
    end

    # @param value [String]
    # @return [String]
    def ext(value)
      case value
      when /^not_found/ then "notfound"
      when /^redirection/ then "redirect"
      else @ext
      end
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

      if value =~ /^not_found/
        value.match(/\d{4}-\d{2}-\d{2}/).to_s
      else
        doc = Nokogiri::XML value
        doc.at("/bibitem/fetched|bibdata/fetched")&.text
      end
    end

    # Returns all items
    # @return [Array<String>]
    def all
      Dir.glob("#{@dir}/**/*.xml").sort.map do |f|
        File.read(f, encoding: "utf-8")
      end
    end

    # Delete item
    # @param key [String]
    def delete(key)
      file = filename key
      f = search_ext(file)
      File.delete f if f
    end

    # Check if version of the DB match to the gem grammar hash.
    # @param fdir [String] dir pathe to flover cache
    # @return [TrueClass, FalseClass]
    def check_version?(fdir)
      version_dir = fdir + "/version"
      return false unless File.exist? version_dir

      v = File.read version_dir, encoding: "utf-8"
      v.strip == grammar_hash(fdir)
    end

    # Set version of the DB to the gem grammar hash.
    # @param fdir [String] dir pathe to flover cache
    # @return [Relaton::DbCache]
    def set_version(fdir)
      file_version = "#{fdir}/version"
      unless File.exist? file_version
        File.write file_version, grammar_hash(fdir), encoding: "utf-8"
      end
      self
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

    protected

    # @param fdir [String] dir pathe to flover cache
    # @return [String]
    def grammar_hash(fdir)
      type = fdir.split("/").last
      Relaton::Registry.instance.by_type(type)&.grammar_hash
    end

    # Reads file by a key
    #
    # @param key [String]
    # @return [String, NilClass]
    def get(key)
      file = filename key
      return unless (f = search_ext(file))

      File.read(f, encoding: "utf-8")
    end

    private

    # Check if a file content is redirection
    #
    # @prarm value [String] file content
    # @return [String, NilClass] redirection code or nil
    def redirect?(value)
      %r{redirection\s(?<code>.*)} =~ value
      code
    end

    # Return item's file name
    # @param key [String]
    # @return [String]
    def filename(key)
      prefcode = key.downcase.match /^(?<prefix>[^\(]+)\((?<code>[^\)]+)/
      fn = if prefcode
             "#{prefcode[:prefix]}/#{prefcode[:code].gsub(/[-:\s\/\()]/, '_').squeeze("_")}"
           else
             key.gsub(/[-:\s]/, "_")
           end
      "#{@dir}/#{fn.sub(/(,|_$)/, '')}"
    end

    #
    # Checks if there is file with xml or txt extension and return filename with
    # the extension.
    #
    # @param file [String]
    # @return [String, NilClass]
    def search_ext(file)
      if File.exist?("#{file}.#{@ext}")
        "#{file}.#{@ext}"
      elsif File.exist? "#{file}.notfound"
        "#{file}.notfound"
      elsif File.exist? "#{file}.redirect"
        "#{file}.redirect"
      end
    end

    # Return item's subdir
    # @param key [String]
    # @return [String]
    def prefix(key)
      key.downcase.match(/^[^\(]+(?=\()/).to_s
    end

    class << self
      private

      def global_bibliocache_name
        "#{Dir.home}/.relaton/cache"
      end

      def local_bibliocache_name(cachename)
        return nil if cachename.nil?

        cachename = "relaton" if cachename.empty?
        "#{cachename}/cache"
      end

      public

      # Initialse and return relaton instance, with local and global cache names
      # local_cache: local cache name; none created if nil; "relaton" created
      # if empty global_cache: boolean to create global_cache
      # flush_caches: flush caches
      def init_bib_caches(opts)
        globalname = global_bibliocache_name if opts[:global_cache]
        localname = local_bibliocache_name(opts[:local_cache])
        localname = "relaton" if localname&.empty?
        if opts[:flush_caches]
          FileUtils.rm_rf globalname unless globalname.nil?
          FileUtils.rm_rf localname unless localname.nil?
        end
        Relaton::Db.new(globalname, localname)
      end
    end
  end
end
