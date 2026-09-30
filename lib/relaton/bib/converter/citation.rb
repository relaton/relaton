# frozen_string_literal: true


module Relaton
  module Bib
    module Converter
      # Citation strings in the three styles relaton-ts renders: ISO 690,
      # Chicago author-date, and APA 7th. All share the same component
      # extraction (one citation language, decomposed title composition,
      # primary identifier, publisher roles).
      module Citation
        STAGE_WORDS = {
          "60.60" => "Published", "60.00" => "Published",
          "50.00" => "Final draft", "50.20" => "Final draft",
          "40.00" => "Draft", "40.20" => "Draft", "90.92" => "Withdrawn",
          "90.93" => "Withdrawn", "95.99" => "Withdrawn",
          "90.60" => "Under review", "60.98" => "Cancelled",
        }.freeze

        class << self
          def iso690(item) = render(item) { |c| c.iso690 }

          def chicago(item) = render(item) { |c| c.chicago }

          def apa(item) = render(item) { |c| c.apa }

          private

          def render(item)
            yield Components.new(item)
          end
        end

        # Extracts the shared citation components once; each style
        # composes them into its own order and punctuation.
        class Components
          attr_reader :docid, :title, :year, :edition, :authors, :org_authors,
                      :publisher, :type

          def initialize(item)
            @type = item.type.to_s
            @docid = primary_docid(item)
            @title = full_title(item)
            @year = published_year(item)
            @edition = item.edition.to_s
            @authors, @org_authors, @publisher = contributors(item)
          end

          def iso690
            if standard?
              bits = [docid, title].reject(&:empty?).join(", ")
              segs(bits, edition.empty? ? "" : "Edition #{edition}", publisher_and_year)
            else
              who = org_authors.empty? ? authors.join(" ; ") : org_authors.first
              segs(who.empty? ? docid : who, title,
                   edition.empty? ? "" : "Edition #{edition}", publisher_and_year)
            end
          end

          def chicago
            who = standard? ? (org_authors.first || publisher || docid) : (authors.first || org_authors.first || docid)
            parts = []
            parts << "#{who}." unless who.empty?
            parts << "#{year}." unless year.empty?
            parts << "#{docid}." if standard? && !docid.empty?
            parts << "#{title}." unless title.empty?
            parts << "#{edition} ed." unless edition.empty? || standard?
            parts << "#{publisher}." unless publisher.empty? || publisher == who
            parts.join(" ")
          end

          def apa
            who = standard? ? (org_authors.first || publisher || docid) : (authors.first || org_authors.first || docid)
            parts = []
            parts << "#{who}." unless who.empty?
            parts << "(#{year})." unless year.empty?
            if title.empty?
              parts << "(#{docid})." unless docid.empty?
            elsif docid.empty?
              parts << "#{title}."
            else
              parts << "#{title} (#{docid})."
            end
            parts << "#{publisher}." unless publisher.empty? || publisher == who
            parts.join(" ")
          end

          private

          def standard? = @type == "standard" || (@type.empty? && !docid.empty?)

          def publisher_and_year
            return year if publisher.empty?

            year.empty? ? publisher : "#{publisher}, #{year}"
          end

          def segs(*parts)
            parts.map { |p| p.to_s.strip }.reject(&:empty?)
              .map { |p| p.end_with?(".") ? p : "#{p}." }
              .join(" ")
          end

          def primary_docid(item)
            ids = Array(item.docidentifier)
            (ids.find(&:primary) || ids.first)&.content.to_s
          end

          def full_title(item)
            titles = Array(item.title).select { |t| t.content.to_s != "" }
            langs = titles.map { |t| t.language.to_s }.uniq
            lang = langs.include?("en") || langs.include?("eng") ? "en" : langs.first
            ours = titles.select { |t| lang.nil? || ["en", "eng"].include?(t.language.to_s) == (lang == "en") || t.language.to_s == lang }
            ours = titles if ours.empty?
            intro = ours.find { |t| t.type == "title-intro" }
            main = ours.find { |t| t.type == "title-main" }
            part = ours.find { |t| t.type == "title-part" }
            composite = ours.find { |t| t.type == "main" }
            base = [intro&.content.to_s, main&.content.to_s].reject(&:empty?)
            base = [composite&.content.to_s].compact if base.empty?
            base.push(part&.content.to_s).reject(&:empty?).join(" — ")
          end

          def published_year(item)
            date = Array(item.date).find { |d| %w[published issued].include?(d.type.to_s) } || item.date.first
            value = date && (date.at || date.from || date.to)
            value.to_s[/\d{4}/]
          end

          def contributors(item)
            authors = []
            org_authors = []
            publisher = ""
            Array(item.contributor).each do |c|
              roles = Array(c.role).map(&:type).compact
              authorish = (roles & %w[author performer editor]).any?
              is_publisher = roles.include?("publisher")
              if authorish && c.person && c.person.name
                authors << person_name(c.person.name)
              elsif authorish && c.organization
                name = org_name(c.organization)
                org_authors << name unless name.empty?
              end
              if is_publisher && c.organization && publisher.empty?
                publisher = org_name(c.organization)
              end
            end
            [authors, org_authors, publisher]
          end

          def person_name(name)
            fore = Array(name.forename).map { |f| f.respond_to?(:content) ? f.content.to_s : f.to_s }.join(" ")
            sur = name.surname.respond_to?(:content) ? name.surname.content.to_s : name.surname.to_s
            return "#{sur}, #{initials(fore)}" unless fore.empty? || sur.empty?
            return sur unless sur.empty?
            complete = name.completename.respond_to?(:content) ? name.completename.content.to_s : name.completename.to_s
            return complete if complete.split.size < 2

            parts = complete.split
            "#{parts[-1]}, #{initials(parts[0...-1].join(' '))}"
          end

          # ISO 690 names: FAMILY, I. I. — given names become initials.
          def initials(forenames)
            forenames.split.map { |w| "#{w[0].upcase}." }.join(" ")
          end

          def org_name(org)
            name = Array(org.name).map { |n| n.respond_to?(:content) ? n.content.to_s : n.to_s }.find(&:itself)
            name || org.abbreviation.to_s
          end
        end
      end
    end
  end
end
