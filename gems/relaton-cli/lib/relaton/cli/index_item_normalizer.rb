module Relaton
  module Cli
    # Turns a Relaton bibliographic YAML document (already parsed to a Hash) into
    # the compact record the index frontend consumes. Works directly off the
    # document's own rendered fields (docidentifier/title/date/ext.doctype), so no
    # per-flavor pubid reconstruction is needed — the data files carry string
    # DocIDs.
    #
    # Output record keys (shared contract with frontend/src/lib/types.ts):
    #   id, title, doctype, stage, date, link, yaml
    module IndexItemNormalizer
      module_function

      # @param doc [Hash] parsed Relaton YAML (string keys)
      # @param lang [String] preferred language for title/docid
      # @param yaml_ref [String, nil] URL/path to the raw YAML source
      # @return [Hash]
      def normalize(doc, lang: "en", yaml_ref: nil)
        {
          "id" => docidentifier(doc, lang),
          "title" => title(doc, lang),
          "doctype" => doctype(doc),
          "stage" => stage(doc),
          "date" => date(doc),
          "link" => link(doc, lang),
          "yaml" => yaml_ref,
        }
      end

      # Pick the primary, preferred-language rendered DocID; fall back to
      # docnumber / id. Values can be plain strings or {content, ...} hashes.
      def docidentifier(doc, lang)
        ids = Array(doc["docidentifier"])
        primary = ids.select { |d| d.is_a?(Hash) && truthy(d["primary"]) }
        primary = ids if primary.empty?

        chosen =
          pick_lang(primary, lang) ||
          primary.find { |d| d.is_a?(Hash) && d["language"].nil? } ||
          primary.first
        strip(content_of(chosen)) || strip(doc["docnumber"]) || doc["id"].to_s
      end

      def title(doc, lang)
        titles = Array(doc["title"])
        # A title entry may be {type: "main", ...} and/or language-tagged.
        main = titles.select { |t| t.is_a?(Hash) && t["type"] == "main" }
        pool = main.empty? ? titles : main
        chosen = pick_lang(pool, lang) || pool.first
        strip(content_of(chosen))
      end

      def doctype(doc)
        dt = doc.dig("ext", "doctype") || doc["doctype"] || doc["type"]
        strip(content_of(dt))
      end

      def stage(doc)
        st = doc.dig("status", "stage") || doc["stage"]
        strip(content_of(st))
      end

      # date: array of {type, at|on} or a plain string. Prefer "published".
      def date(doc)
        dates = doc["date"]
        return normalize_date(dates) if dates.is_a?(String)

        arr = Array(dates)
        chosen = arr.find { |d| d.is_a?(Hash) && d["type"] == "published" } ||
                 arr.find { |d| d.is_a?(Hash) } || arr.first
        val = chosen.is_a?(Hash) ? (chosen["at"] || chosen["on"] || chosen["from"]) : chosen
        normalize_date(val)
      end

      # Human-facing link: prefer a citation source in the preferred language.
      def link(doc, lang)
        sources = Array(doc["source"]) + Array(doc["link"])
        return nil if sources.empty?

        citation = sources.select do |s|
          s.is_a?(Hash) && %w[citation web src].include?(s["type"])
        end
        pool = citation.empty? ? sources : citation
        chosen = pick_lang(pool, lang) || pool.first
        strip(content_of(chosen))
      end

      # --- helpers -------------------------------------------------------------

      def pick_lang(entries, lang)
        entries.find do |e|
          e.is_a?(Hash) && (e["language"] == lang || Array(e["language"]).include?(lang))
        end
      end

      # Extract a display string from a value that may be a String or a Hash with
      # a "content"/"name" key (recursing into arrays/hashes as needed).
      def content_of(value)
        case value
        when String then value
        when Hash then content_of(value["content"] || value["name"])
        when Array then content_of(value.first)
        end
      end

      def normalize_date(value)
        return nil if value.nil?

        s = value.to_s.strip
        return nil if s.empty?

        # Keep YYYY, YYYY-MM, or YYYY-MM-DD as-is (leading 10 chars).
        s[0, 10]
      end

      # Strip inline HTML (e.g. <sup>) so records are clean for JSON/data-attrs.
      def strip(value)
        return nil if value.nil?

        s = value.to_s.gsub(/<[^>]+>/, "").strip
        s.empty? ? nil : s
      end

      def truthy(value)
        value == true || value == "true"
      end
    end
  end
end
