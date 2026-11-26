# frozen_string_literal: true

module Relaton
  module Bib
    module Converter
      module Endnote
        class FromEndnote
          TAG_LINE = /\A%([A-Z@]) (.*)\z/

          # @param refer_str [String]
          # @return [Hash{String=>Relaton::Bib::ItemData}] keyed by the
          #   first title (Refer has no identifier tag), falling back to
          #   the record position
          def self.parse(refer_str)
            refer_str.split(/\n\s*\n/).map(&:lines).reject(&:empty?)
              .each_with_object({}).with_index do |(record_lines, hash), i|
              item = new(record_lines).item
              title = Array(item.title).first&.content.to_s
              hash[title.empty? ? "record-#{i + 1}" : title] = item
            end
          end

          # @param record_lines [Array<String>]
          def initialize(record_lines)
            @tags = Hash.new { |h, k| h[k] = [] }
            record_lines.each do |line|
              next unless (m = line.chomp.match(TAG_LINE))

              @tags[m[1]] << m[2]
            end
          end

          # @return [Relaton::Bib::ItemData]
          def item
            ItemData.new(
              docidentifier: fetch_docid,
              title: fetch_title,
              date: fetch_date,
              contributor: fetch_contributor,
              edition: fetch_edition,
              series: fetch_series,
              keyword: fetch_keyword,
              source: fetch_source,
            )
          end

          private

          # Refer has no identifier tag; a %R is some dialects' report
          # number, not a docidentifier — none is invented here.
          def fetch_docid
            []
          end

          def fetch_title
            @tags["T"].map { |v| Title.new(type: "title-main", content: v) }
          end

          # Refer dates are "YYYY" or a free-form date string.
          def fetch_date
            @tags["D"].map do |v|
              on = v.match?(/\A\d{4}\z/) ? v : (::Date.parse(v).to_s rescue v)
              Bib::Date.new(type: "published", at: on)
            end
          end

          # "Surname, Forename" names a person; a bare token is an
          # organization (the same convention the RIS importer applies to
          # this converter's own output).
          def fetch_contributor
            contribs = []
            @tags["A"].each do |name|
              contribs << if name.include?(",")
                            person_contributor(name)
                          else
                            org_contributor(name, "author")
                          end
            end
            @tags["I"].each { |name| contribs << org_contributor(name, "publisher") }
            contribs
          end

          def person_contributor(name)
            parts = name.split(", ")
            surname = LocalizedString.new(content: parts.first)
            forename = (parts[1] || "").split.map { |fn| FullNameType::Forename.new(content: fn) }
            person = Person.new(name: FullName.new(surname: surname, forename: forename))
            Contributor.new(person: person, role: [Contributor::Role.new(type: "author")])
          end

          def org_contributor(name, role)
            org = Organization.new(name: [TypedLocalizedString.new(content: name)])
            Contributor.new(organization: org, role: [Contributor::Role.new(type: role)])
          end

          def fetch_edition
            Edition.new(content: @tags["@"].first.to_s) if @tags["@"].any?
          end

          def fetch_series
            series = []
            @tags["J"].each { |v| series << Series.new(type: "journal", title: Title.new(content: v)) }
            @tags["S"].each { |v| series << Series.new(title: Title.new(content: v)) }
            series
          end

          def fetch_keyword
            @tags["K"].map { |v| Keyword.new(vocab: [LocalizedString.new(content: v)]) }
          end

          def fetch_source
            @tags["U"].map { |v| Uri.new(type: "src", content: v) }
          end
        end
      end
    end
  end
end
