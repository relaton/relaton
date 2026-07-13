# frozen_string_literal: true

module Relaton
  module Sdo
    # One logo variant for an organization. Variants are differentiated by
    # `style` (the primary discriminator — e.g. "default", "red", "iso_1972"),
    # `format` (file suffix) and `size`. `applicability` is opaque, informational
    # text (e.g. "stage>=60"); the store never interprets it — consumers do.
    class Logo
      MIME_TYPES = {
        "png" => "image/png",
        "jpg" => "image/jpeg",
        "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "svg" => "image/svg+xml",
        "webp" => "image/webp",
        "eps" => "application/postscript",
        "pdf" => "application/pdf",
      }.freeze

      attr_reader :style, :format, :size, :url, :applicability

      def initialize(style: nil, format: nil, size: nil, url: nil, applicability: nil)
        @style = style
        @format = format
        @size = size
        @url = url
        @applicability = applicability
      end

      def self.from_hash(hash)
        new(style: hash["style"], format: hash["format"], size: hash["size"],
            url: hash["url"], applicability: hash["applicability"])
      end

      # Raw binary content of the logo, fetched lazily from `url` and memoized.
      # Raises Sdo::Error (naming the URL) if the fetch fails, rather than
      # returning nil and crashing cryptically inside data_uri/save downstream.
      def content
        @content ||= begin
          data = Fetcher.download(url)
          raise Error, "could not fetch logo from #{url.inspect}" if data.nil?

          data
        end
      end

      # The logo as a base64-encoded data URI, ready to embed in XML/HTML.
      def data_uri
        "data:#{mimetype};base64,#{Base64.strict_encode64(content)}"
      end

      def mimetype
        MIME_TYPES[format.to_s.downcase] || "application/octet-stream"
      end

      # Write the logo to disk. With no argument, uses a filename derived from
      # the source URL (or from style/size/format); returns the path written.
      def save(path = nil)
        path ||= default_filename
        File.binwrite(path, content)
        path
      end

      def to_h
        { style: style, format: format, size: size, url: url,
          applicability: applicability }.compact
      end

      def describe
        to_h.map { |k, v| "#{k}=#{v}" }.join(", ")
      end

      private

      def default_filename
        base = File.basename(url_path)
        return base unless base.empty? || File.extname(base).empty?

        stem = [style, size].reject { |s| s.to_s.empty? }.join("-")
        stem = "logo" if stem.empty?
        ext = format.to_s.empty? ? "bin" : format
        "#{stem}.#{ext}"
      end

      # The URL's path component, tolerating URLs that URI can't parse (e.g. a
      # stray space) by falling back to the raw string sans query/fragment.
      def url_path
        URI.parse(url.to_s).path
      rescue URI::InvalidURIError
        url.to_s.split(/[?#]/, 2).first
      end
    end
  end
end
