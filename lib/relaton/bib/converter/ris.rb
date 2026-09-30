# frozen_string_literal: true


module Relaton
  module Bib
    module Converter
      # RIS serialization — the interchange format for EndNote, Zotero,
      # and Reference Manager. Standards map to TY - STD.
      module Ris
        ENTRY_TYPES = {
          "standard" => "STD", "book" => "BOOK", "article" => "JOUR",
          "inbook" => "CHAP", "inproceedings" => "CONF", "report" => "RPRT",
          "thesis" => "THES", "website" => "ELEC", "webresource" => "ELEC",
        }.freeze

        def self.from_item(item)
          Renderer.new(item).to_s
        end

        class Renderer
          def initialize(item)
            @item = item
          end

          def to_s
            lines = ["TY  - #{ENTRY_TYPES[@item.type.to_s] || 'STD'}"]
            add_authors(lines)
            add_field(lines, "TI", primary_title)
            add_field(lines, "ID", primary_docid)
            add_field(lines, "PY", published_year)
            add_field(lines, "ET", @item.edition&.to_s)
            lang = Array(@item.language).first
            add_field(lines, "LA", lang.to_s)
            Array(@item.keyword).each { |k| add_field(lines, "KW", k.content.to_s) }
            add_field(lines, "UR", source_uri)
            lines << "ER  - "
            lines.join("\r\n") + "\r\n"
          end

          private

          def add_field(lines, tag, value)
            lines << "#{tag}  - #{value}" if value && !value.empty?
          end

          def add_authors(lines)
            Array(@item.contributor).each do |c|
              roles = Array(c.role).map(&:type).compact
              authorish = (roles & %w[author performer editor]).any?
              publisher = roles.include?("publisher")
              if authorish && c.person
                out = person_display_name(c.person.name)
                lines << "AU  - #{out}" unless out.empty?
              elsif authorish && c.organization
                out = org_name(c.organization)
                lines << "AU  - #{out}" unless out.empty?
              elsif publisher && c.organization
                out = org_name(c.organization)
                lines << "PB  - #{out}" unless out.empty? || lines.any? { |l| l.start_with?("PB  - ") }
              end
            end
          end

          def person_display_name(name)
            return "" unless name

            fore = Array(name.forename).map { |f| f.respond_to?(:content) ? f.content.to_s : f.to_s }.join(" ")
            sur = name.surname.respond_to?(:content) ? name.surname.content.to_s : name.surname.to_s
            complete = name.completename.respond_to?(:content) ? name.completename.content.to_s : name.completename.to_s
            return "#{sur}, #{fore}" unless fore.empty? || sur.empty?
            return sur unless sur.empty?

            complete
          end

          def org_name(org)
            name = Array(org.name).map { |n| n.respond_to?(:content) ? n.content.to_s : n.to_s }.find(&:itself)
            name || org.abbreviation.to_s
          end

          def primary_title
            Citation::Components.title_of(@item)
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
