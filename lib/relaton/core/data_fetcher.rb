require "fileutils"

module Relaton
  module Core
    class DataFetcher
      # attr_accessor :docs
      #
      # Initialize fetcher
      #
      # @param [String] output path to output directory
      # @param [String] format output format (yaml, xml, bibxml)
      #
      def initialize(output, format)
        @output = output
        @format = format
        @ext = format.sub "bibxml", "xml"
        @files = Set.new
      # path => docid that reserved it, for #unique_output_file. Distinct from
      # @files, which flavors use for their own duplicate handling: this one has
      # to know WHICH document owns a path, not just that it is taken.
      @file_docids = {}
        # @docs = []
        @errors = Hash.new(true)
      end

      # API method for external service
      #
      # @return the value returned by the instance `#fetch`, so callers can act
      #   on the outcome (e.g. relaton-iso returns whether it rebuilt).
      def self.fetch(source = nil, output: "data", format: "yaml")
        t1 = Time.now
        puts "Started at: #{t1}"
        FileUtils.mkdir_p output
        result = new(output, format).fetch(source)
        t2 = Time.now
        puts "Stopped at: #{t2}"
        puts "Done in: #{(t2 - t1).round} sec."
        result
      end

      def fetch(source = nil)
        raise NotImplementedError, "#{self.class}#fetch method must be implemented"
      end

      def gh_issue
        return @gh_issue if defined? @gh_issue

        channel = gh_issue_channel
        if channel[0]
          @gh_issue = Relaton::Logger::Channels::GhIssue.new(*channel)
          Relaton.logger_pool[:gh_issue] = Relaton::Logger::Log.new(@gh_issue, levels: [:error])
        end
        @gh_issue
      end

      def gh_issue_channel
        [ENV.fetch("GITHUB_REPOSITORY", nil), "Error fetching documents"]
      end

      def report_errors
        gh_issue # register the channel before logging
        @errors.select { |_, v| v }.each do |key, value|
          # A String value IS the message: a specific, per-document failure
          # such as an unparseable identifier, reported through this same
          # channel without needing a per-flavor override. A boolean means
          # "this field failed for every record" — what the flavors' own
          # ERROR_KEYS track — and its message is derived from the key.
          log_error value.is_a?(String) ? value : "Failed to fetch #{key}"
        end
        @gh_issue&.create_issue
      end

      def log_error(_msg)
        raise NoMatchingPatternError, "#{self.class}#log_error method must be implemented"
      end

      # Most filesystems cap a single path component at 255 bytes.
      MAX_BASENAME_BYTES = 255

      # @param [String] document ID
      # @return [String] filename based on PubID identifier
      #
      # A docid can be pathologically long (pubid's `to_s` for amendment docs
      # embeds the full "(Amendment to … as amended by …)" clause), which would
      # make the basename exceed the OS limit and raise Errno::ENAMETOOLONG on
      # write. When that happens, truncate the sanitized id and append a short
      # digest of the full docid so the filename stays bounded, unique, and
      # deterministic (every call site round-trips through this method).
      def output_file(docid)
        id = docid.downcase.gsub(/[.,\s\/:()-]+/, "-").delete_suffix("-")
        ext = ".#{@ext}"
        limit = MAX_BASENAME_BYTES - ext.bytesize
        if id.bytesize > limit
          require "digest"
          suffix = "-#{Digest::SHA1.hexdigest(docid)[0, 12]}"
          # `id` has no consecutive "-" (gsub collapsed runs above), so
          # truncation leaves at most one trailing "-" — delete_suffix is
          # enough and avoids a polynomial-ReDoS regex on the docid.
          id = id.byteslice(0, limit - suffix.bytesize).scrub("").delete_suffix("-") + suffix
        end
        File.join @output, "#{id}#{ext}"
      end

      #
      # Reserve a unique output path for `docid`.
      #
      # `output_file` sanitizes ".", ",", "/", ":", "(", ")", "-" and whitespace
      # all to "-", so two DISTINCT docids can map to one path — live instance in
      # relaton-data-iana: `rpki/signed-objects` and `rpki-signed-objects` both
      # give `data/rpki-signed-objects.yaml`. A caller that merely warns and
      # writes anyway leaves one file holding the wrong document for one of two
      # index ids: a wrong answer, not a missing one.
      #
      # Returns `output_file(docid)` when that path is free, or when it is
      # already held by this SAME docid — a genuine duplicate is the caller's
      # business (skip / merge / last-wins), and this method must not turn one
      # into two files. Only a real clash with a DIFFERENT docid gets a variant,
      # suffixed with a digest of this docid so the name depends on the document
      # and not on encounter order: adding a record never renames an existing
      # file. (Which member of a clashing pair keeps the plain path does follow
      # write order, which is stable for a given corpus.)
      #
      # @param [String] docid
      # @return [String] path, reserved for this docid
      #
      def unique_output_file(docid)
        file = output_file docid
        owner = @file_docids[file]
        file = digest_output_file(docid) unless owner.nil? || owner == docid
        @file_docids[file] ||= docid
        file
      end

      #
      # Serialize bibliographic item
      #
      # @param [RelatonCcsds::BibliographicItem] bib <description>
      #
      # @return [String] serialized bibliographic item
      #
      def serialize(bib)
        send "to_#{@format}", bib
      end

      def to_yaml(bib)
        raise NotImplementedError, "#{self.class}#to_yaml method must be implemented"
      end

      def to_xml(bib)
        raise NotImplementedError, "#{self.class}#to_xml method must be implemented"
      end

      def to_bibxml(bib)
        raise NotImplementedError, "#{self.class}#to_bibxml method must be implemented"
      end

      private

      # `output_file`'s path with a docid digest appended to the basename, kept
      # inside the same byte cap. Deterministic: same docid, same name.
      def digest_output_file(docid)
        require "digest"
        ext = ".#{@ext}"
        suffix = "-#{Digest::SHA1.hexdigest(docid)[0, 12]}"
        stem = File.basename output_file(docid), ext
        limit = MAX_BASENAME_BYTES - ext.bytesize - suffix.bytesize
        stem = stem.byteslice(0, limit).scrub("").delete_suffix("-") if stem.bytesize > limit
        File.join @output, "#{stem}#{suffix}#{ext}"
      end
    end
  end
end
