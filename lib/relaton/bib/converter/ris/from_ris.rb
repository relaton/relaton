# frozen_string_literal: true

module Relaton
  module Bib
    module Converter
      module Ris
        # One TY..ER record per entry; tags are `XX  - value` lines.
        class FromRis
          # ELEC backs two entry types; the reverse pairs it with the
          # webresource face the renderer's default pairs with.
          REVERSE_ENTRY_TYPES = {
            "STD" => "standard", "BOOK" => "book", "JOUR" => "article",
            "CHAP" => "inbook", "CONF" => "inproceedings", "RPRT" => "report",
            "THES" => "thesis", "ELEC" => "webresource",
          }.freeze

          TAG_LINE = /\A([A-Z0-9]{2})  - ?(.*)\z/

          # @param ris_str [String]
          # @return [Hash{String=>Relaton::Bib::ItemData}] keyed by the ID
          #   tag (falling back to the docidentifier, then the record
          #   position)
          def self.parse(ris_str)
            records = []
            current = nil
            ris_str.each_line do |line|
              line = line.chomp
              if line.start_with?("TY  - ")
                current = [line]
              elsif current
                current << line
                # The renderer writes "ER  - " with a trailing space; real
                # files commonly stop at the dash.
                if line.start_with?("ER  -")
                  records << current
                  current = nil
                end
              end
            end
            records.each_with_object({}).with_index do |(record, hash), i|
              item = new(record).item
              hash[record_key(item) || "record-#{i + 1}"] = item
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
              type: entry_type,
              docidentifier: fetch_docid,
              title: fetch_title,
              date: fetch_date,
              contributor: fetch_contributor,
              edition: fetch_edition,
              language: @tags["LA"].map(&:itself),
              keyword: fetch_keyword,
              source: fetch_source,
            )
          end

          # @return [String, nil] the primary docidentifier's content
          def self.record_key(item)
            ids = Array(item.docidentifier)
            primary = (ids.find(&:primary) || ids.first)&.content.to_s
            primary unless primary.empty?
          end

          private

          def entry_type
            REVERSE_ENTRY_TYPES.fetch(@tags["TY"].first, "standard")
          end

          def fetch_docid
            @tags["ID"].map { |v| Docidentifier.new(content: v, primary: true) }
          end

          def fetch_title
            @tags["TI"].map { |v| Title.new(type: "title-main", content: v) }
          end

          # RIS dates are "YYYY" or "YYYY/MM/DD".
          def fetch_date
            @tags["PY"].map do |v|
              on = v.match?(/\A\d{4}\z/) ? v : (::Date.parse(v.tr("/", "-")).to_s rescue v)
              Bib::Date.new(type: "published", at: on)
            end
          end

          # The renderer emits "Surname, Forename" for persons and a bare
          # name for organizations under the same AU tag; a comma splits a
          # person, a bare token is an organization name.
          def fetch_contributor # rubocop:disable Metrics/AbcSize
            contribs = []
            @tags["AU"].each do |name|
              contribs << if name.include?(",")
                            person_contributor(name)
                          else
                            org_contributor(name, "author")
                          end
            end
            @tags["PB"].each { |name| contribs << org_contributor(name, "publisher") }
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
            Edition.new(content: @tags["ET"].first.to_s) if @tags["ET"].any?
          end

          def fetch_keyword
            @tags["KW"].map { |v| Keyword.new(vocab: LocalizedString.new(content: v)) }
          end

          def fetch_source
            @tags["UR"].map { |v| Uri.new(type: "src", content: v) }
          end
        end
      end
    end
  end
end
