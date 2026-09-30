# frozen_string_literal: true

require "json"

module Relaton
  module Bib
    module Converter
      # CSL-JSON serialization — the Citation Style Language interchange
      # format consumed by Zotero, Mendeley, and every citeproc.
      module Csl
        ENTRY_TYPES = {
          "standard" => "standard", "book" => "book",
          "article" => "article-journal", "inbook" => "chapter",
          "inproceedings" => "paper-conference", "report" => "report",
          "thesis" => "thesis", "website" => "webpage",
          "webresource" => "webpage",
        }.freeze

        def self.from_item(item)
          Renderer.new(item).to_s
        end

        class Renderer
          def initialize(item)
            @item = item
          end

          def to_s
            out = {}
            docid = primary_docid
            out[:id] = docid.empty? ? "relaton" : docid
            out[:type] = ENTRY_TYPES[@item.type.to_s] || "standard"
            out[:title] = primary_title unless primary_title.empty?
            authors = csl_authors
            out[:author] = authors unless authors.empty?
            out[:issued] = { "date-parts" => [[published_year]] } unless published_year.empty?
            publisher = publisher_name
            out[:publisher] = publisher unless publisher.empty?
            out[:number] = docid unless docid.empty?
            out[:edition] = @item.edition.to_s unless @item.edition.to_s.empty?
            lang = Array(@item.language).first
            out[:language] = lang.to_s if lang
            keywords = Array(@item.keyword).map { |k| k.content.to_s }.reject(&:empty?)
            out[:keyword] = keywords unless keywords.empty?
            out[:URL] = source_uri if source_uri
            [out].to_json + "\n"
          end

          private

          def csl_authors
            Array(@item.contributor).filter_map do |c|
              roles = Array(c.role).map(&:type).compact
              next unless (roles & %w[author performer editor]).any?

              if c.person
                name = c.person.name
                fore = name ? Array(name.forename).map { |f| f.respond_to?(:content) ? f.content.to_s : f.to_s }.join(" ") : ""
                sur = name && name.surname.respond_to?(:content) ? name.surname.content.to_s : name&.surname.to_s
                complete = name && name.completename.respond_to?(:content) ? name.completename.content.to_s : name&.completename.to_s
                if sur.to_s.empty?
                  complete.to_s.empty? ? nil : { "literal" => complete }
                else
                  entry = { "family" => sur }
                  entry["given"] = fore unless fore.empty?
                  entry
                end
              elsif c.organization
                literal = org_name(c.organization)
                literal.empty? ? nil : { "literal" => literal }
              end
            end
          end

          def org_name(org)
            name = Array(org.name).map { |n| n.respond_to?(:content) ? n.content.to_s : n.to_s }.find(&:itself)
            name || org.abbreviation.to_s
          end

          def publisher_name
            pub = Array(@item.contributor).find do |c|
              Array(c.role).map(&:type).include?("publisher") && c.organization
            end
            pub ? org_name(pub.organization) : ""
          end

          def primary_title
            titles = Array(@item.title).select { |t| t.content.to_s != "" }
            en = titles.find { |t| t.language.to_s == "eng" || t.language.to_s == "en" }
            (en || titles.first)&.content.to_s
          end

          def primary_docid
            ids = Array(@item.docidentifier)
            (ids.find(&:primary) || ids.first)&.content.to_s
          end

          def published_year
            date = Array(@item.date).find { |d| %w[published issued].include?(d.type.to_s) } || @item.date.first
            value = date && (date.at || date.from || date.to)
            value.to_s[/\d{4}/]
          end

          def source_uri
            Array(@item.source).map { |s| s.respond_to?(:content) ? s.content.to_s : s.to_s }
              .find { |u| u.start_with?("http") }
          end
        end
      end
    end
  end
end
