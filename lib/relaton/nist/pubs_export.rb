require "yeptris"
require "singleton"

module Relaton
  module Nist
    class PubsExport
      include Singleton

      DOMAIN = "https://csrc.nist.gov".freeze
      PUBS_EXPORT = URI.join(DOMAIN, "/CSRC/media/feeds/metanorma/pubs-export")
      # The default cache location. The live location is #datafile, which
      # follows Relaton::Index.config.storage_dir (default Dir.home).
      DATAFILEDIR = File.expand_path ".relaton/nist", Dir.home
      DATAFILE = File.expand_path "pubs-export.zip", DATAFILEDIR

      def initialize
        @mutex = Mutex.new
      end

      #
      # Fetches json data form server
      #
      # @return [Array<Hash>] json data
      #
      def data
        @mutex.synchronize do
          @data ||= begin
            ctime = File.ctime datafile if File.exist? datafile
            if !ctime || ctime.to_date < ::Date.today || File.size(datafile).zero?
              fetch_data(ctime)
            end
            unzip
          end
        end
      end

      #
      # The cache file of the pubs-export zip. It lives under the same root as
      # the relaton-index cache, so one setting moves both (for example to a
      # writable directory on a read-only host).
      #
      # @return [String]
      #
      def datafile
        dir = Dir.home
        dir = Relaton::Index.config.storage_dir if defined?(Relaton::Index)
        File.expand_path "pubs-export.zip", File.join(dir, ".relaton", "nist")
      end

      private

      #
      # Fetch data form server and save it to file. When the cache file cannot
      # be written (a read-only file system, such as AWS Lambda —
      # relaton-nist#57), keep the downloaded zip in memory for this process.
      #
      # @param ctime [Time, nil] file creation time
      #
      def fetch_data(ctime)
        return unless !ctime || ctime < last_modified

        @data = nil
        zip = download
        begin
          write_datafile zip
          @buffer = nil
        rescue SystemCallError, IOError => e
          Util.warn "Cannot write `#{datafile}` (#{e.message}); " \
                    "the CSRC pubs-export data stays in memory"
          @buffer = zip
        end
      end

      #
      # Write the zip to a temp file and rename it into place, so a failed
      # write (a full disk) never leaves a truncated cache that later
      # processes would read as fresh.
      #
      # @param zip [String] zip file content
      #
      def write_datafile(zip)
        FileUtils.mkdir_p File.dirname(datafile)
        tmp = "#{datafile}.#{Process.pid}.tmp"
        File.binwrite tmp, zip
        File.rename tmp, datafile
      ensure
        FileUtils.rm_f tmp if tmp && File.exist?(tmp)
      end

      def download
        uri_open = URI.method(:open) || Kernel.method(:open)
        uri_open.call("#{PUBS_EXPORT}.zip", &:read)
      end

      def last_modified
        uri = URI("#{PUBS_EXPORT}.meta")
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          Time.httpdate(http.head(uri.request_uri)["last-modified"])
        end
      end

      #
      # upack zip file (the in-memory copy when the cache was not writable)
      #
      # @return [Array<Hash>] json data
      #
      def unzip
        if @buffer
          # open_buffer returns the buffer, not the block's value
          rows = nil
          Zip::File.open_buffer(StringIO.new(@buffer)) do |zf|
            rows = read_entry zf
          end
          @buffer = nil
          rows
        else
          Zip::File.open(datafile) { |zf| read_entry zf }
        end
      end

      # The block form closes the entry stream. Without it the cache file
      # stays open, and Windows then refuses to replace or delete it.
      def read_entry(zip_file)
        Relaton::Json.parse_external zip_file.first.get_input_stream(&:read)
      end
    end
  end
end
