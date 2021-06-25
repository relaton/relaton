require "aws-sdk-s3"

module Relaton
  #
  # Man
  #
  class Storage
    include Singleton

    def initialize
      if Relaton.configuration.api_mode
        @s3 = Aws::S3::Client.new
      end
    end

    #
    # Save file to storage
    #
    # @param dir [String]
    # @param key [String]
    # @param value [String]
    #
    def save(dir, key, value)
      set_version dir
      if Relaton.configuration.api_mode
        @s3.put_object bucket: ENV["AWS_BUCKET"], key: key, body: value
      else
        file_safe_write key, value
      end
    end

    #
    # Returns all items
    #
    # @param dir [String]
    #
    # @return [Array<String>]
    #
    def all(dir)
      if Relaton.configuration.api_mode
        list = @s3.list_objects_v2 bucket: ENV["AWS_BUCKET"], prefix: dir
        list.contents.select { |i| i.key.match?(/\.xml$/) }.sort_by(&:key).map do |item|
          content = s3_read item.key
          block_given? ? yield(item.key, content) : content
        end
      else
        Dir.glob("#{dir}/**/*.{xml,yml,yaml}").sort.map do |f|
          content = File.read(f, encoding: "utf-8")
          block_given? ? yield(f, content) : content
        end
      end
    end

    # Delete item
    # @param key [String]
    def delete(key)
      f = search_ext(key)
      File.delete f if f
    end

    # Check if version of the DB match to the gem grammar hash.
    # @param fdir [String] dir pathe to flover cache
    # @return [Boolean]
    def check_version?(fdir)
      file_version = "#{fdir}/version"
      if Relaton.configuration.api_mode
        begin
          v = s3_read file_version
        rescue Aws::S3::Errors::NoSuchKey
          return false
        end
      else
        return false unless File.exist? fdir

        v = File.read file_version, encoding: "utf-8"
      end

      v.strip == grammar_hash(fdir)
    end

    # Reads file by a key
    #
    # @param key [String]
    # @return [String, NilClass]
    def get(key)
      return unless (f = search_ext(key))

      if Relaton.configuration.api_mode
        s3_read f
      else
        File.read(f, encoding: "utf-8")
      end
    end

    private

    #
    # Read file form AWS S#
    #
    # @param [String] key file name
    #
    # @return [String] content
    #
    def s3_read(key)
      obj = @s3.get_object bucket: ENV["AWS_BUCKET"], key: key
      obj.body.read
    end

    #
    # Checks if there is file with xml or txt extension and return filename with
    # the extension.
    #
    # @param file [String]
    # @return [String, NilClass]
    def search_ext(file)
      if Relaton.configuration.api_mode
        fs = @s3.list_objects_v2 bucket: ENV["AWS_BUCKET"], prefix: "#{file}."
        fs.contents.first&.key
      # elsif File.exist?("#{file}.#{@ext}")
      #   "#{file}.#{@ext}"
      # elsif File.exist? "#{file}.notfound"
      #   "#{file}.notfound"
      # elsif File.exist? "#{file}.redirect"
      #   "#{file}.redirect"
      else
        Dir["#{file}.*"].first
      end
    end

    # Set version of the DB to the gem grammar hash.
    # @param fdir [String] dir pathe to flover cache
    def set_version(fdir)
      file_version = "#{fdir}/version"
      if Relaton.configuration.api_mode
        begin
          @s3.head_object bucket: ENV["AWS_BUCKET"], key: file_version
        rescue Aws::S3::Errors::NotFound
          @s3.put_object(bucket: ENV["AWS_BUCKET"], key: file_version,
                         body: grammar_hash(fdir))
        end
      else
        FileUtils::mkdir_p fdir unless Dir.exist?(fdir)
        unless File.exist? file_version
          file_safe_write file_version, grammar_hash(fdir)
        end
      end
    end

    # @param file [String]
    # @content [String]
    def file_safe_write(file, content)
      File.open file, File::RDWR | File::CREAT, encoding: "UTF-8" do |f|
        Timeout.timeout(10) { f.flock File::LOCK_EX }
        f.write content
      end
    end

    # @param fdir [String] dir pathe to flover cache
    # @return [String]
    def grammar_hash(fdir)
      type = fdir.split("/").last
      Relaton::Registry.instance.by_type(type)&.grammar_hash
    end
  end
end
