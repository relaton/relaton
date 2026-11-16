# frozen_string_literal: true

module Relaton
  module Bib
    module Converter
      module Endnote
        class ToEndnote
          # @param item [Relaton::Bib::ItemData]
          def initialize(item)
            @item = item
          end

          # @return [String] one Refer record (no trailing blank line)
          def to_s
            lines = []
            add_authors(lines)
            add_field(lines, "%T", primary_title)
            add_field(lines, "%D", published_year)
            add_field(lines, "%@", @item.edition&.to_s)
            add_field(lines, "%I", publisher_name)
            add_journal(lines)
            add_series(lines)
            Array(@item.keyword).each { |k| add_field(lines, "%K", k.vocab.content.to_s) }
            add_field(lines, "%U", source_uri)
            lines.join("\n") + "\n"
          end

          private

          def add_field(lines, tag, value)
            lines << "#{tag} #{value}" if value && !value.empty?
          end

          # The same authorish/publisher split the RIS renderer makes.
          def add_authors(lines)
            Array(@item.contributor).each do |c|
              roles = Array(c.role).map(&:type).compact
              authorish = (roles & %w[author performer editor]).any?
              if authorish && c.person
                out = person_display_name(c.person.name)
                add_field(lines, "%A", out) unless out.empty?
              elsif authorish && c.organization
                out = org_name(c.organization)
                add_field(lines, "%A", out) unless out.empty?
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

          def publisher_name
            pub = Array(@item.contributor).find do |c|
              Array(c.role).map(&:type).include?("publisher") && c.organization
            end
            pub && org_name(pub.organization)
          end

          # %J is the journal series; %S a plain series. An item carries at
          # most one of each in this mapping.
          def add_journal(lines)
            journal = Array(@item.series).find { |s| s.type == "journal" }
            add_field(lines, "%J", series_title(journal)) if journal
          end

          def add_series(lines)
            series = Array(@item.series).reject { |s| s.type == "journal" }.first
            add_field(lines, "%S", series_title(series)) if series
          end

          def series_title(series)
            Array(series.title).map { |t| t.respond_to?(:content) ? t.content.to_s : t.to_s }.find(&:itself)
          end

          def primary_title
            Titles.of(@item)
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
