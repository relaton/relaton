require "nokogiri"
require_relative "id_parser"

module Relaton::Bipm
  class SiBrochureParser
    #
    # Create new parser
    #
    # @param [Relaton::Bipm::DataFetcher] data_fetcher data fetcher
    #
    def initialize(data_fetcher)
      @data_fetcher = WeakRef.new data_fetcher
    end

    #
    # Parse documents from SI brochure dataset and write thems to YAML files
    #
    # @param [Relaton::Bipm::DataFetcher] data_fetcher data fetcher
    #
    def self.parse(data_fetcher)
      new(data_fetcher).parse
    end

    #
    # Parse SI brochure and write them to YAML files
    #
    def parse # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # metanorma site generate writes per-document outputs into a subdirectory
      # named after the source path (e.g. _site/documents/si-brochure/3.01/
      # si-brochure-en.rxl). The legacy top-level *.rxl glob is kept for
      # backwards compatibility with any older flow that flattened outputs.
      si_brochure_rxls.each do |f|
        puts "Parsing #{f}"
        xml = File.read(f, encoding: "UTF-8")
        xml = xml.force_encoding("UTF-8") if xml.encoding != Encoding::UTF_8
        item1 = Bibdata.from_xml(xml)
        # Workaround for relaton-bib Version#content bug: whitespace between
        # legacy <revision-date>/<draft> children gets captured as @content,
        # blocking the legacy-fold path. Clear it so the getter recomputes.
        item1.version.each do |v|
          c = v.instance_variable_get(:@content)
          next unless c.is_a?(Array) || (c.is_a?(String) && c.strip.empty?)
          v.instance_variable_set(:@content, nil)
        end
        @data_fetcher.errors[:si_brochure_title] &&= item1.title.empty?
        @data_fetcher.errors[:si_brochure_docidentifier] &&= item1.docidentifier.empty?
        unless has_committee_contributor?(item1)
          contribs = extract_editorialgroup(xml)
          contribs.each { |c| item1.contributor << c }
        end
        fix_si_brochure_id item1
        basename = File.join @data_fetcher.output, File.basename(f).sub(/(?:-(?:en|fr))?\.rxl$/, "")
        outfile = "#{basename}.#{@data_fetcher.ext}"
        key = item1.docnumber || basename
        @data_fetcher.index.add_or_update Id.new.parse(key).to_hash, outfile
        item =
          if File.exist? outfile
            warn_duplicate = false
            item2 = Item.from_yaml File.read(outfile, encoding: "UTF-8")
            fix_si_brochure_id item2
            hash1 = YAML.safe_load item1.to_yaml
            hash2 = YAML.safe_load item2.to_yaml
            Item.from_yaml deep_merge(hash1, hash2).to_yaml
          else
            warn_duplicate = true
            item1
          end
        @data_fetcher.write_file outfile, item, warn_duplicate: warn_duplicate
        puts "Saved to #{outfile}"
      end
    end

    #
    # @return [Array<String>] paths to SI Brochure RXL files. Looks at the
    #   legacy flat layout first, then the metanorma-cli subdirectory layout
    #   (`<source_path_without_'sources'>/<doc>.rxl`) used by current
    #   `metanorma site generate` output.
    #
    def si_brochure_rxls
      flat = Dir["bipm-si-brochure/_site/documents/*.rxl"]
      return flat if flat.any?

      Dir["bipm-si-brochure/_site/documents/**/si-brochure-{en,fr}.rxl"]
    end

    #
    # Update ID of SI brochure
    #
    # @param [ItemData] item bibliographic item
    #
    # @return [void]
    #
    def fix_si_brochure_id(item)
      # isbn = hash["docid"].detect { |id| id["type"] == "ISBN" }
      # num = isbn && isbn["id"] == "978-92-822-2272-0" ?  "SI Brochure" : "SI Brochure, Appendix 4"

      update_id item

      prid = primary_id item
      if item.docnumber
        item.docnumber.sub!(/^Brochure(?:\sConcise|\sFAQ)?$/i, prid.sub(/^BIPM\s/, ""))
      else
        item.docnumber = prid.sub(/^BIPM\s/, "")
      end
      item.id = prid.gsub(/[,\s-]/, "")
    end

    def update_id(item)
      item.docidentifier.each do |id|
        next unless id.type == "BIPM" && id.content&.match?(/BIPM Brochure/i)

        id.primary = true
        id.content.sub!(/(?<=^BIPM\s)(Brochure)/i, "SI \\1")
      end
    end

    def primary_id(item)
      item.docidentifier.detect do |id|
        id.primary && (id.language == "en" || id.language.nil?)
      end.content
    end

    def has_committee_contributor?(item)
      item.contributor.any? do |c|
        c.role.any? { |r| r.description.any? { |d| d.content == "committee" } }
      end
    end

    def extract_editorialgroup(xml)
      doc = Nokogiri::XML(xml)
      doc.xpath("//editorialgroup/committee").map do |committee|
        acronym = committee["acronym"]
        names = committee.xpath("variant").map do |v|
          Relaton::Bib::TypedLocalizedString.new(
            content: v.text, language: v["language"], script: v["script"],
          )
        end
        subdiv = Relaton::Bib::Subdivision.new(
          type: "committee", name: names,
          abbreviation: Relaton::Bib::LocalizedString.new(content: acronym),
        )
        bipm_name = [Relaton::Bib::TypedLocalizedString.new(content: acronym)]
        org = Relaton::Bib::Organization.new(name: bipm_name, subdivision: [subdiv])
        desc = Relaton::Bib::LocalizedMarkedUpString.new(content: "committee")
        role = Relaton::Bib::Contributor::Role.new(type: "author", description: [desc])
        Relaton::Bib::Contributor.new(organization: org, role: [role])
      end
    end

    #
    # Deep merge two hashes
    #
    # @param [Hash] hash1
    # @param [Hash] hash2
    #
    # @return [Hash] Merged hash
    #
    def deep_merge(hash1, hash2) # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
      hash1.merge(hash2) do |_, oldval, newval|
        if oldval.is_a?(Hash) && newval.is_a?(Hash)
          deep_merge(oldval, newval)
        elsif oldval.is_a?(Array) && newval.is_a?(Array)
          (oldval + newval).uniq { |i| downcase_all i }
        else
          newval || oldval
        end
      end
    end

    #
    # Downcase all values in hash or array
    #
    # @param [Array, Hash, String] content hash, array or string
    #
    # @return [Array, Hash, String] hash, array or string with downcased values
    #
    def downcase_all(content)
      case content
      when Hash then content.transform_values { |v| downcase_all v }
      when Array then content.map { |v| downcase_all v }
      when String then content.downcase
      else content
      end
    end
  end
end
