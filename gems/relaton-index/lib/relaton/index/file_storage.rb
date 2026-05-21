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
        File.write file, data, encoding: "UTF-8"
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
