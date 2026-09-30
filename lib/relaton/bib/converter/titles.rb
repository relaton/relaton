# frozen_string_literal: true

module Relaton
  module Bib
    module Converter
      # Single citation language; decomposed titles compose, composite or
      # plain titles stand alone. Shared by every export converter.
      module Titles
        def self.of(item)
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
      end
    end
  end
end
