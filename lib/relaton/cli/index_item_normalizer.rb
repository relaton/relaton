module Relaton
  module Cli
    # Turns a Relaton bibliographic YAML document (already parsed to a Hash) into
    # the compact record the index frontend consumes. Works directly off the
    # document's own rendered fields (docidentifier/title/date/ext.doctype), so no
    # per-flavor pubid reconstruction is needed — the data files carry string
    # DocIDs.
    #
    # Output record keys (shared contract with frontend/src/lib/types.ts):
    #   id, title, doctype, stage, date, link, yaml  (always present) plus the
    #   optional detail-page fields (only when non-empty): abstract, edition,
    #   languages, keywords, publisher, contributors, docids, dates, relations.
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
        }.merge(details(doc, lang))
      end

      # Richer, structured fields the detail page renders. Empty/nil values are
      # dropped so a summary-only doc keeps the compact core shape and the
      # embedded JSON payload stays lean. These ride only in the embedded
      # payload; search.json and the crawler DOM stay summary-only.
      def details(doc, lang)
        {
          "abstract" => abstract(doc, lang),
          "edition" => edition(doc),
          "languages" => languages(doc),
          "keywords" => keywords(doc),
          "publisher" => publisher(doc, lang),
          "contributors" => contributors(doc, lang),
          "docids" => docids(doc),
          "dates" => dates(doc),
          "relations" => relations(doc, lang),
        }.reject { |_, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
      end

      # Pick the primary, preferred-language rendered DocID; fall back to
      # docnumber / id. Values can be plain strings or {content, ...} hashes.
      def docidentifier(doc, lang)
        primary_docidentifier(doc, lang) || strip(doc["docnumber"]) || doc["id"].to_s
      end

      # Just the rendered primary DocID, with no docnumber/id fallback — nil when
      # the item carries no docidentifier. Split out because a relation's target
      # needs the DocID *only*: its `id` is an internal XML anchor, which must not
      # outrank the formattedref (see `relation_id`).
      def primary_docidentifier(doc, lang)
        ids = wrap(doc["docidentifier"])
        primary = ids.select { |d| d.is_a?(Hash) && truthy(d["primary"]) }
        primary = ids if primary.empty?

        chosen =
          pick_lang(primary, lang) ||
          primary.find { |d| d.is_a?(Hash) && d["language"].nil? } ||
          primary.first
        strip(content_of(chosen))
      end

      def title(doc, lang)
        titles = wrap(doc["title"])
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

        arr = wrap(dates)
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

      # --- detail-page fields --------------------------------------------------

      # Preferred-language abstract (String or [{language, content}]), HTML-stripped.
      def abstract(doc, lang)
        value = doc["abstract"]
        return strip(value) if value.is_a?(String)

        entries = Array(value)
        strip(content_of(pick_lang(entries, lang) || entries.first))
      end

      def edition(doc)
        strip(content_of(doc["edition"]))
      end

      # The document's language codes, e.g. ["en", "fr"].
      def languages(doc)
        wrap(doc["language"]).map { |l| strip(content_of(l)) }.compact
      end

      def keywords(doc)
        wrap(doc["keyword"]).map { |k| strip(content_of(k)) }.compact
      end

      # Name of the first publisher-role contributor, if any.
      def publisher(doc, lang)
        entry = wrap(doc["contributor"]).find { |c| role?(c, "publisher") }
        entry && contributor_name(entry, lang)
      end

      # All contributors as {name, role}. Entries without a resolvable name are
      # skipped so the detail page never shows a blank author line.
      def contributors(doc, lang)
        wrap(doc["contributor"]).filter_map { |c| contributor(c, lang) }
      end

      def contributor(entry, lang)
        return nil unless entry.is_a?(Hash)

        name = contributor_name(entry, lang)
        return nil unless name

        role = strip(content_of(roles_of(entry).first))
        { "name" => name, "role" => role }.reject { |_, v| v.nil? }
      end

      # Prefer an organization name, then a person name, then a bare "name".
      def contributor_name(entry, lang)
        org = entry["organization"]
        return org_name(org, lang) if org.is_a?(Hash)

        person = entry["person"]
        return person_name(person, lang) if person.is_a?(Hash)

        strip(content_of(entry["name"]))
      end

      def org_name(org, lang)
        names = wrap(org["name"])
        strip(content_of(pick_lang(names, lang) || names.first))
      end

      def person_name(person, lang)
        name = person["name"]
        return strip(content_of(name)) unless name.is_a?(Hash)

        complete = name["completename"] || name["completeName"]
        return strip(content_of(pick_lang(wrap(complete), lang) || complete)) if complete

        given = strip(content_of(name["forename"] || name["given"]))
        surname = strip(content_of(name["surname"]))
        joined = [given, surname].compact.join(" ")
        joined.empty? ? nil : joined
      end

      # role[].type for a contributor, as an array of raw values.
      def roles_of(entry)
        roles = entry["role"]
        roles = [roles] unless roles.is_a?(Array)
        roles.map { |r| r.is_a?(Hash) ? r["type"] : r }
      end

      def role?(entry, type)
        return false unless entry.is_a?(Hash)

        roles_of(entry).any? { |r| strip(content_of(r)) == type }
      end

      # Every docidentifier as {id, type?, language?} (blank ids dropped).
      def docids(doc)
        wrap(doc["docidentifier"]).filter_map do |d|
          id = strip(content_of(d))
          next nil unless id

          hash = d.is_a?(Hash) ? d : {}
          { "id" => id,
            "type" => strip(content_of(hash["type"])),
            "language" => strip(content_of(hash["language"])) }
            .reject { |_, v| v.nil? }
        end
      end

      # Every date as {type?, value}; a plain string date becomes {value}.
      def dates(doc)
        value = doc["date"]
        entries = value.is_a?(String) ? [value] : wrap(value)
        entries.filter_map { |d| date_entry(d) }
      end

      def date_entry(entry)
        unless entry.is_a?(Hash)
          val = normalize_date(entry)
          return val && { "value" => val }
        end

        val = normalize_date(entry["at"] || entry["on"] || entry["from"])
        return nil unless val

        { "type" => strip(content_of(entry["type"])), "value" => val }
          .reject { |_, v| v.nil? }
      end

      # Related documents as {type, id}, e.g. {"type" => "obsoletedBy",
      # "id" => "ISO 29862:2024"}. The id is what the detail page matches against
      # the rest of the corpus to decide whether the relation can be rendered as
      # an intra-dataset link, so it must be rendered exactly as a document's own
      # `id` is — hence the shared `docidentifier` helper below.
      #
      # Self-references are dropped (BIPM's Metrologia articles relate to
      # themselves once per carrier, which would render as a link to the page you
      # are already on) and identical {type, id} pairs are collapsed.
      def relations(doc, lang)
        own = docidentifier(doc, lang)
        wrap(doc["relation"])
          .filter_map { |r| relation(r, lang) }
          .reject { |r| r["id"] == own }
          .uniq
      end

      def relation(entry, lang)
        return nil unless entry.is_a?(Hash)

        id = relation_id(entry["bibitem"], lang)
        return nil unless id

        { "type" => strip(content_of(entry["type"])), "id" => id }.reject { |_, v| v.nil? }
      end

      # A relation's bibitem carries the same docidentifier shape as a top-level
      # document, so the primary-DocID logic is shared — that is what makes the
      # emitted id string-identical to the dataset id it must match.
      #
      # Order matters. `docidentifier` is NOT reused whole: its last fallback is
      # the item's `id`, which on a relation bibitem is an internal XML anchor
      # ("CENISO/TS21003-7-2008/A1-2010", as CEN records carry). That anchor can
      # never match a document in the corpus, so letting it outrank the rendered
      # formattedref would strand a target that IS present as plain text under a
      # mangled label. The anchor stays only as the last resort.
      def relation_id(bibitem, lang)
        return strip(content_of(bibitem)) unless bibitem.is_a?(Hash)

        primary_docidentifier(bibitem, lang) ||
          strip(content_of(bibitem["formattedref"])) ||
          strip(bibitem["docnumber"]) ||
          strip(bibitem["id"])
      end

      # --- helpers -------------------------------------------------------------

      # Wrap a value as an array WITHOUT `Array()`'s Hash-to-pairs explosion: a
      # bare Hash (a single unwrapped entry) becomes a one-element array, not a
      # list of [key, value] pairs. RelatonBib normally emits arrays for these
      # repeatable fields, but a hand-written YAML may carry a lone Hash.
      def wrap(value)
        case value
        when nil then []
        when Array then value
        else [value]
        end
      end

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
        when Numeric then value.to_s
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
      #
      # Counts angle brackets in one left-to-right pass instead of using a
      # regex, because both regex spellings are wrong here:
      #
      #   * `gsub(/<[^>]+>/, "")` matches ACROSS a nested `<`, so on
      #     "<sc<x>ript>" it removes the outer span "<sc<x>" and lets the
      #     fragments either side of the tag it walked over close back up into
      #     "ript>" (CodeQL rb/incomplete-multi-character-sanitization);
      #   * narrowing to `/<[^<>]*>/` matches innermost-first and fixes that,
      #     but then one pass no longer suffices and re-running to a fixed point
      #     is quadratic — each pass peels a single nesting level off the whole
      #     string. Measured at 0.7s for 8k chars of "<"*n + ">"*n, i.e. a real
      #     ReDoS traded for the theoretical one the scanner flagged.
      #
      # This is O(n) with no backtracking and nothing to re-scan. `pending`
      # holds the span opened by the outermost unclosed `<` so that a bare "<"
      # that never closes survives as literal text ("5 < 6") rather than
      # swallowing the rest of the value; a bare ">" is likewise kept.
      def strip(value)
        return nil if value.nil?

        s = strip_tags(value.to_s).strip
        s.empty? ? nil : s
      end

      def strip_tags(str)
        return str unless str.include?("<")

        out = +""
        pending = +""
        depth = 0

        str.each_char do |char|
          if char == "<"
            depth += 1
          elsif depth.zero?
            # Outside any tag — including a stray ">", which is not markup.
            out << char
            next
          elsif char == ">"
            depth -= 1
          end

          pending << char
          pending.clear if depth.zero? # the span closed: drop it wholesale
        end

        depth.zero? ? out : out << pending
      end

      def truthy(value)
        value == true || value == "true"
      end
    end
  end
end
