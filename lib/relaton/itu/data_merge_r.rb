require_relative "../itu"

module Relaton
  module Itu
    # Incremental write path for harvested ITU-R records (issue #75).
    #
    # The ITU-R dataset cannot be rebuilt from scratch — DataCrawlerR reads the
    # pages ITU still serves, and those expose **less** than the decommissioned
    # RunSearch feed did. Two consequences drive this module:
    #
    # 1. **A published date must never be rewritten.** A Recommendation page
    #    carries only its approval date, while the preserved record holds the
    #    publication date RunSearch served — measured on the whole BO series,
    #    those differ for every record and the *year* differs for 59% of them.
    #    Overwriting would change which edition answers a dated reference. (A
    #    Report page does carry the publication date, so reports reproduce it;
    #    the rule costs nothing there.)
    # 2. **A harvest is a partial view.** Only the families the crawler
    #    implements are seen, so a run must add and backfill, never delete, and
    #    must leave untouched records byte-identical so the data repo's diff
    #    shows only what actually changed.
    #
    # Merge rules, applied per record: `date` is kept as published, always;
    # `title` and `source` are filled in only when the published record has
    # none; everything else is left alone. A record whose published counterpart
    # has a **different doctype** is a collision — an ITU-R report and
    # recommendation in the same series can share a docidentifier, and therefore
    # a filename — so it is reported and skipped rather than silently
    # overwriting the other document.
    module DataMergeR
      extend self

      #
      # Merge harvested records into the dataset the fetcher writes to.
      #
      # @param items [Array<Relaton::Itu::ItemData>] as DataCrawlerR#harvest returns
      # @param fetcher [Relaton::Itu::DataFetcher] supplies output_file/write_file
      #   and the index, so harvested records get the same pubid guard and
      #   unparseable-id reporting as the ITU-T harvest
      #
      # @return [Hash] { added:, backfilled:, unchanged:, skipped:,
      #   collisions: [[file, published_doctype, harvested_doctype], …] }
      #
      def write_all(items, fetcher)
        stats = { added: 0, backfilled: 0, unchanged: 0, skipped: 0, collisions: [] }
        seen = {}
        items.each do |bib|
          id = primary_id(bib)
          unless id
            stats[:skipped] += 1
            Util.error "ITU-R merge: record with no primary docidentifier skipped"
            next
          end

          file = fetcher.output_file id
          # First writer of a filename keeps it; a later claimant is reported and
          # dropped, never merged into a document it isn't.
          if (other = seen[file])
            record_collision stats, file, other, "#{id} (#{doctype bib})", "this harvest"
            next
          end
          seen[file] = "#{id} (#{doctype bib})"
          merge_one bib, id, file, fetcher, stats
        rescue => e # rubocop:disable Style/RescueStandardError
          # One unreadable published file must not discard an hour of crawling.
          stats[:skipped] += 1
          Util.error "ITU-R merge: #{id || '(no id)'} skipped: #{e.message}"
        end
        stats
      end

      private

      # @return [void]
      def merge_one(bib, id, file, fetcher, stats)
        unless File.exist? file
          fetcher.write_file bib
          stats[:added] += 1
          return
        end

        published = Item.from_yaml File.read(file, encoding: "UTF-8")
        published_id = primary_id published
        # Both halves matter: a different doctype means a report and a
        # recommendation share a filename, and a different id means two docids
        # sanitize to one filename (`output_file` collapses `.`, `/` and spaces
        # alike, so `ITU-R BO.4/BL/4` and `ITU-R BO.4-BL-4` would meet here).
        if doctype(published) != doctype(bib) || published_id != id
          record_collision stats, file, "#{published_id} (#{doctype published})",
                           "#{id} (#{doctype bib})", "the published dataset"
          return
        end

        if backfill published, bib
          fetcher.write_file published
          stats[:backfilled] += 1
        else
          # Not rewritten: an identical re-serialization would churn the data
          # repo's diff. Index it anyway — the index is rebuilt from scratch on
          # every run, so a record that is not written still has to be in it.
          # Indexed by the id the *file* carries, as #index_files does.
          fetcher.index_primary published_id, file
          stats[:unchanged] += 1
        end
      end

      # Fill only what the published record is missing. `date` is deliberately
      # absent from this list — see the module comment.
      #
      # @param published [Relaton::Itu::Item] mutated in place
      # @param bib [Relaton::Itu::ItemData] the harvested record
      # @return [Boolean] whether anything was filled in
      def backfill(published, bib)
        filled = false
        if published.source.nil? || published.source.empty?
          published.source = bib.source
          filled ||= !(bib.source.nil? || bib.source.empty?)
        end
        if published.title.nil? || published.title.empty?
          published.title = bib.title
          filled ||= !(bib.title.nil? || bib.title.empty?)
        end
        filled
      end

      # @return [void]
      def record_collision(stats, file, kept, dropped, where)
        stats[:skipped] += 1
        stats[:collisions] << [file, kept, dropped]
        Util.error "ITU-R merge: filename collision on #{file} — #{kept} in #{where} vs " \
                   "harvested #{dropped}; not overwritten"
      end

      # Strictly the primary docid: DataFetcher#write_file reads
      # `docidentifier.find(&:primary).content` with no fallback, so a record
      # without one has nowhere to be written and is skipped here instead.
      #
      # @return [String, nil]
      def primary_id(bib)
        bib.docidentifier.find(&:primary)&.content
      end

      # @return [String, nil]
      def doctype(bib)
        bib.ext&.doctype&.content
      end
    end
  end
end
