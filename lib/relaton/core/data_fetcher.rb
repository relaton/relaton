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
        # path => docid that reserved it, for #unique_output_file. Distinct
        # from @files, which flavors use for their own duplicate handling:
        # this one has to know WHICH document owns a path, not just that it
        # is taken.
        @file_docids = {}
        # Paths this process wrote during this run; see #write_unique.
        @written = Set.new
        # Set true by a fetcher that writes from forked worker processes,
        # where @file_docids cannot see a peer's claim. See #write_unique.
        @cross_process = false
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

      # Create-or-fail. The failure is the point: it is how one process learns
      # that another already holds a path. See #write_unique.
      EXCLUSIVE = File::WRONLY | File::CREAT | File::EXCL

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
        reserve file, docid
      end

      #
      # Write `content` for `docid`, never clobbering a different document.
      #
      # `output_file` is not injective, so the plain path may belong to someone
      # else. `unique_output_file` settles that within this process; the file is
      # then created with `O_EXCL` so a peer *process* cannot be clobbered
      # either. Returns the path actually written.
      #
      # The four outcomes, each load-bearing:
      #
      # * **We already wrote this path for this docid** — plain overwrite, so a
      #   genuine duplicate stays one file and the flavor's own duplicate
      #   handling (skip / merge / last-wins) still decides what happens.
      # * **`O_EXCL` succeeds** — the normal case.
      # * **`EEXIST`, single process** — `unique_output_file` has already proved
      #   that no peer of ours holds this path, so the file can only be a
      #   leftover from an earlier crawl. Overwrite it. Every single-process
      #   flavor takes this branch, and it involves no guesswork.
      # * **`EEXIST`, `@cross_process`** — a peer's file and a leftover are
      #   indistinguishable, so take a path of our own rather than risk
      #   destroying a record. The caller reconciles the names afterwards, in
      #   the parent, where it can see every docid (see
      #   `Relaton::Ietf::DataFetcher#reconcile_output_files`).
      #
      # Deliberately NOT a wall-clock "is this file older than the crawl?" test.
      # A crawl runs into a populated `data/`, so `EEXIST` is the common case on
      # a re-run and such a test would decide it for every record; its
      # false-"stale" direction is the silent overwrite this method exists to
      # prevent, and coarse filesystem mtime granularity makes that reachable.
      #
      # @param [String] docid
      # @param [String] content serialized document
      # @return [String] path written
      #
      def write_unique(docid, content)
        file = unique_output_file docid
        return force_write(file, content) if @written.include?(file)

        File.write file, content, mode: EXCLUSIVE, encoding: "UTF-8"
        @written << file
        file
      rescue Errno::EEXIST
        return force_write(file, content) unless @cross_process

        force_write reserve(digest_output_file(docid), docid), content
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

      # Write, clobbering whatever is there. The caller has already established
      # that the path is ours to take.
      def force_write(file, content)
        File.write file, content, encoding: "UTF-8"
        @written << file
        file
      end

      # Record `docid` as the owner of `file`, unless someone got there first,
      # and return `file`. The reservation table must never hand one path to two
      # documents; see #unique_output_file.
      def reserve(file, docid)
        @file_docids[file] ||= docid
        file
      end

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
