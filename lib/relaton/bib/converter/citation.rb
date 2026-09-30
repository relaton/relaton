# frozen_string_literal: true

require "liquid"
require "yaml"

module Relaton
  module Bib
    module Converter
      # Citations rendered from the ISO 690 metaschema: the standard
      # defines the component inventory of every citation (originator,
      # date, title, edition, place, publisher, extent, series,
      # identifier, access), and each citation style is a profile that
      # selects, orders, and punctuates those components. Styles are
      # liquid templates plus a name form in styles.yml — adding a style
      # adds files, never engine code (Citation.register for
      # out-of-gem styles).
      # A citation style is a capsule: a directory with style.yml (its
      # name form) and templates/ (liquid, keyed by resource type). The
      # engine discovers capsules under formats/ and treats a registered
      # external capsule identically — including the ItemData#to_#{style}
      # delegate — so built-ins and extensions are indistinguishable and
      # adding a style edits no existing file.
      module Citation
        FORMATS_DIR = File.expand_path("citation/formats", __dir__)

        class << self
          def profiles
            @profiles ||= {}
          end

          def styles
            profiles.keys
          end

          def render(item, style:)
            profile = profiles.fetch(style.to_sym) do
              raise ArgumentError, "unknown citation style: #{style}"
            end
            components = Components.new(item, name_format: profile.fetch(:name_format))
            fields = components.fields
            template = Liquid::Template.parse(template_for(fields[:type_key], profile))
            cleanup(template.render(fields.transform_keys(&:to_s)))
          end

          def register(style, name_format:, templates_dir:)
            profiles[style.to_sym] = { name_format:, templates_dir: }
            define_item_delegate(style.to_sym)
          end

          private

          def discover!
            Dir[File.join(FORMATS_DIR, "*", "style.yml")].each do |manifest|
              dir = File.dirname(manifest)
              register(File.basename(dir).to_sym,
                name_format: YAML.load_file(manifest).fetch("name_format"),
                templates_dir: File.join(dir, "templates"))
            end
          end

          def define_item_delegate(style)
            return if Relaton::Bib::ItemData.method_defined?(:"to_#{style}")

            Relaton::Bib::ItemData.define_method(:"to_#{style}") { Citation.render(self, style:) }
          end

          def template_for(type_key, profile)
            dir = profile[:templates_dir]
            specific = File.join(dir, "#{type_key}.liquid")
            path = File.exist?(specific) ? specific : File.join(dir, "default.liquid")
            File.read(path)
          end

          def cleanup(text)
            out = text.gsub(/\s+\./, ".").gsub(/\.\s*\./, ".").gsub(/\s+,/, ",")
                      .gsub(/\(\s*\)/, "").strip
            out.empty? || out.end_with?(".", "!", "?") ? out : "#{out}."
          end
        end

        discover!

        # Extracts the ISO 690 component inventory from a Relaton item as
        # display-ready values. One citation language, decomposed title
        # composition, primary identifier; names are formatted per the
        # style's name form so templates stay pure placement.
        class Components
          # Name forms are the second extension surface: a capsule's
          # style.yml names one, new forms register here.
          NAME_FORMATS = {
            "surname_initials" => ->(n) { "#{n[:family]}, #{initials(n[:given])}" },
            "family_given" => ->(n) { "#{n[:family]}, #{n[:given]}" },
            "family_initials" => ->(n) { "#{n[:family]}, #{initials(n[:given])}" },
          }.freeze

          def initialize(item, name_format:)
            @item = item
            @name_format = name_format
          end

          # Liquid truthiness: only nil and false are falsy, so empty
          # strings and arrays are nulled here for {% if %} to work.
          def fields
            {
              type_key: type_key,
              docid: primary_docid,
              title: self.class.title_of(@item),
              year: published_year,
              edition: @item.edition.to_s,
              place: Array(@item.place).first.to_s,
              publisher: publisher_name,
              lead: lead_originator,
              trailing_publisher: trailing_publisher,
              authors: author_names,
              org_authors: org_author_names,
              access_url: source_uri,
            }.transform_values { |v| v.respond_to?(:empty?) && v.empty? ? nil : v }
          end

          def self.initials(given)
            given.split.map { |w| "#{w[0].upcase}." }.join(" ")
          end

          private

          def type_key
            @item.type.to_s.empty? ? "standard" : @item.type.to_s
          end

          def name_parts(person_name)
            return { family: "", given: "", complete: "" } unless person_name

            given = Array(person_name.forename).map { |f| f.respond_to?(:content) ? f.content.to_s : f.to_s }.join(" ")
            family = person_name.surname.respond_to?(:content) ? person_name.surname.content.to_s : person_name.surname.to_s
            complete = person_name.completename.respond_to?(:content) ? person_name.completename.content.to_s : person_name.completename.to_s
            { family: family.to_s, given: given.to_s, complete: complete.to_s }
          end

          def format_name(person_name)
            parts = name_parts(person_name)
            return "" if parts[:family].empty? && parts[:complete].empty?

            if parts[:family].empty?
              words = parts[:complete].split
              return words.first if words.size < 2

              parts = { family: words.last, given: words[0...-1].join(" "), complete: parts[:complete] }
            end
            NAME_FORMATS.fetch(@name_format.to_s).call(parts)
          end

          def author_names
            Array(@item.contributor).filter_map do |c|
              roles = Array(c.role).map(&:type).compact
              next unless (roles & %w[author performer editor]).any? && c.person

              format_name(c.person.name)
            end.reject(&:empty?)
          end

          def org_author_names
            Array(@item.contributor).filter_map do |c|
              roles = Array(c.role).map(&:type).compact
              next unless (roles & %w[author performer editor]).any? && c.organization

              org_name(c.organization)
            end.reject(&:empty?)
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

          def lead_originator
            if standard?
              org_author_names.first || publisher_name || primary_docid
            else
              author_names.first || org_author_names.first || primary_docid
            end
          end

          def trailing_publisher
            publisher_name.empty? || publisher_name == lead_originator ? "" : publisher_name
          end

          def standard? = type_key == "standard"

          def primary_docid
            ids = Array(@item.docidentifier)
            (ids.find(&:primary) || ids.first)&.content.to_s
          end

          # One citation language; decomposed titles compose, a composite
          # or plain title stands alone. Shared by every export converter.
          def self.title_of(item)
            titles = Array(item.title).select { |t| t.content.to_s != "" }
            content = ->(t) { t&.content.to_s }
            intro = titles.find { |t| t.type == "title-intro" }
            main = titles.find { |t| t.type == "title-main" }
            part = titles.find { |t| t.type == "title-part" }
            composite = titles.find { |t| t.type == "main" }
            base = [content.call(intro), content.call(main)].reject(&:empty?)
            base = [content.call(composite)].reject(&:empty?) if base.empty?
            base = [content.call(titles.first)].reject(&:empty?) if base.empty?
            [*base, content.call(part)].reject(&:empty?).join(" — ")
          end

          def published_year
            date = Array(@item.date).find { |d| %w[published issued].include?(d.type.to_s) } || Array(@item.date).first
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
