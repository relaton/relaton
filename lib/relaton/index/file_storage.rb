module Relaton
  module Index
    #
    # File storage module contains methods to read and write files
    #
    module FileStorage
      #
      # Return file creation time
      #
      # @param [String] file file path
      #
      # @return [Time, nil] file creation time or nil if file does not exist
      #
      def ctime(file)
        File.exist?(file) && File.ctime(file)
      end

      #
      # Read file
      #
      # @param [String] file file path
      #
      # @return [String, nil] file content or nil if file does not exist
      #
      def read(file)
        return unless File.exist?(file)

        File.read file, encoding: "UTF-8"
      end

      #
      # Write file
      #
      # @param [String] file file path
      # @param [String] data content to write
      #
      # @return [void]
      #
      def write(file, data)
        dir = File.dirname file
        FileUtils.mkdir_p dir
        # Write the bytes verbatim. `data` is often a raw Net::HTTP body, an
        # ASCII-8BIT string; passing `encoding: "UTF-8"` would *transcode* it and
        # raise Encoding::UndefinedConversionError on any non-ASCII byte (e.g. a
        # UTF-8 `\xC3` in "électrotechnique"). The bytes are already valid UTF-8
        # and `read` decodes them as UTF-8, so a binary write round-trips.
        File.binwrite file, data
      end

      #
      # Remove file
      #
      # @param [String] file file path
      #
      # @return [void]
      #
      def remove(file)
        return unless File.exist? file

        File.delete file
      end

      extend self
    end
  end
end
