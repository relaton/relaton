require "json"
require "net/http"
require "openssl"
require "zlib"

module Relaton
  module Index
    #
    # Reads a flavor's machine index from its GitHub Pages site (relaton#189).
    #
    # `index/manifest.json` gives the lookup rule, and a query reads only the
    # one `index/shard-NNNNN.json` its document family lives in, in place of the
    # whole `index-vN.zip`. The shard key is `crc32(id.root.number.to_s) %
    # shards`, the expression the relaton-cli producer (`MachineIndex`) writes
    # and `Type#candidates_by_number` narrows on. See
    # `docs/data-repository-format.adoc`, "The machine index on the Pages site".
    #
    # Everything is held in memory for TTL seconds and never written to the
    # storage. A shard 404 is a definitive "not found" (empty buckets are not
    # published). A transport failure raises `Relaton::RequestError`, which
    # `Relaton::Db#net_retry` retries; a machine index this client cannot read
    # raises `Relaton::Index::Error`. Neither falls back to the monolith: the
    # whole index is read only when the manifest publishes no shards, or when
    # the query has no root number to key on.
    #
    class ShardSource
      TTL = 24 * 60 * 60
      VERSION = 2
      KEY = "root-number".freeze
      ALGORITHM = "crc32".freeze

      NET_ERRORS = [
        SocketError, Timeout::Error, IOError, SystemCallError, OpenSSL::SSL::SSLError,
        Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError,
        Zlib::Error # a truncated gzip body, which Net::HTTP inflates

      ].freeze

      attr_reader :pages_url

      #
      # @param [String] dir flavor directory name, used in log messages
      # @param [String] pages_url base URL of the Pages site, with a trailing `/`
      # @param [Class] pubid_class the flavor's pubid identifier class
      #
      def initialize(dir, pages_url, pubid_class)
        @pages_url = pages_url.end_with?("/") ? pages_url : "#{pages_url}/"
        # Only the deserialization helpers are used: this FileIO reads and
        # writes no file.
        @file_io = FileIO.new(dir, nil, nil, nil, pubid_class)
        @mutex = Mutex.new
        @state = nil
      end

      #
      # Rows of the shard that holds the document family of `id`.
      #
      # @param [Pubid::Identifier] id parsed query
      #
      # @return [Array<Hash>] `{ id:, file: }` rows, empty when not found
      #
      def rows(id)
        number = id.root.number.to_s
        state = current_state
        shards = manifest(state)["shards"]
        return load_whole_index(state) if shards.zero? || number.empty?

        n = Zlib.crc32(number) % shards
        once(state, n) { fetch_shard(n) }
      end

      #
      # Every row, from the monolith the manifest names (`<index>.zip` on the
      # Pages site). Needed by a String query and a block-only search.
      #
      # @return [Array<Hash>] `{ id:, file: }` rows, sorted by root number
      #
      def whole_index
        load_whole_index current_state
      end

      private

      # One generation of cached data. It is replaced as a whole when it
      # expires, so a fetch that finishes late stores into its own generation
      # and never mixes an old shard with a new manifest.
      def new_state
        { created: Time.now, data: {}, locks: {} }
      end

      def current_state
        @mutex.synchronize do
          @state = new_state if @state.nil? || Time.now - @state[:created] > TTL
          @state
        end
      end

      # Runs the block once for each key in a generation. The network call is
      # made under a lock for that key only, so lookups of other shards (from
      # the `Relaton::Db` workers pool) do not wait for it. A raise stores
      # nothing, so the next call tries again.
      def once(state, key)
        lock = @mutex.synchronize { state[:locks][key] ||= Mutex.new }
        lock.synchronize do
          data = state[:data]
          return @mutex.synchronize { data[key] } if @mutex.synchronize { data.key?(key) }

          value = yield
          @mutex.synchronize { data[key] = value }
        end
      end

      def manifest(state)
        once(state, :manifest) do
          body = get("index/manifest.json")
          raise Error, "no machine index manifest at `#{url('index/manifest.json')}`" unless body

          check_manifest parse_json(body, "index/manifest.json")
        end
      end

      def check_manifest(data)
        unless data.is_a?(Hash) && data["version"] == VERSION &&
            data["key"] == KEY && data["algorithm"] == ALGORITHM &&
            data["shards"].is_a?(Integer) && !data["shards"].negative? &&
            data["index"].is_a?(String) && !data["index"].empty?
          raise Error, "unsupported machine index manifest at " \
                       "`#{url('index/manifest.json')}`: #{data.inspect}"
        end

        data
      end

      def fetch_shard(num)
        path = format("index/shard-%05d.json", num)
        body = get(path)
        return [] unless body

        data = parse_json(body, path)
        raise Error, "shard `#{url(path)}` is not an array" unless data.is_a?(Array)

        data.map { |r| { id: deserialize(r["id"], path), file: r["file"] } }
      end

      def load_whole_index(state)
        path = "#{manifest(state)['index']}.zip"
        once(state, :whole_index) do
          body = get(path)
          raise Error, "no whole index at `#{url(path)}`" unless body

          yaml = unzip(body)
          raise Error, "empty archive at `#{url(path)}`" unless yaml

          index = YAML.safe_load(yaml, permitted_classes: [Symbol])
          raise Error, "wrong structure of `#{url(path)}`" unless @file_io.check_basic_format(index)

          @file_io.deserialize_pubid(index)
        rescue FileIO::InvalidIndexError, Psych::SyntaxError, Zip::Error, Zlib::Error => e
          raise Error, "cannot read `#{url(path)}`: #{e.message}"
        end
      end

      def unzip(body)
        yaml = nil
        # `open_buffer` does not return the block's value.
        Zip::File.open_buffer(body) { |zip| yaml = zip.entries.first&.get_input_stream&.read }
        yaml
      end

      def deserialize(raw, path)
        @file_io.deserialize_id(raw)
      rescue FileIO::InvalidIndexError => e
        raise Error, "cannot read shard `#{url(path)}`: #{e.message}"
      end

      def parse_json(body, path)
        JSON.parse(body)
      rescue JSON::ParserError => e
        raise Error, "cannot parse `#{url(path)}`: #{e.message}"
      end

      def url(path)
        "#{@pages_url}#{path}"
      end

      #
      # @return [String, nil] the body, or nil for a 404
      #
      def get(path)
        resp = Net::HTTP.get_response(URI.parse(url(path)))
        case resp.code
        when "200" then resp.body
        when "404" then nil
        else raise Relaton::RequestError, "Could not access #{url(path)}: HTTP #{resp.code}"
        end
      rescue *NET_ERRORS => e
        raise Relaton::RequestError, "Could not access #{url(path)}: #{e.message}"
      end
    end
  end
end
