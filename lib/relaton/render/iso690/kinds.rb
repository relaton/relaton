# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      # The vocabulary mapping from a bibliographic item's wire type value
      # to its ISO 690 clause 8 resource kind (TemplateType). This table is
      # the engine's charter — style instances select perType templates on
      # kinds and never enumerate type synonyms. Unmapped values fall to
      # the report kind (clause 8.11), the runner's fallback.
      module Kinds
        TO_KIND = {
          "book" => "monograph",
          "booklet" => "monograph",
          "manual" => "monograph",
          "proceedings" => "monograph",
          "thesis" => "monograph",
          "standard" => "report",
          "techreport" => "report",
          "report" => "report",
          "patent" => "patent",
          "journal" => "continuing",
          "serial" => "continuing",
          "article-journal" => "continuing",
          "article-magazine" => "continuing",
          "inbook" => "component_part",
          "incollection" => "component_part",
          "inproceedings" => "component_part",
          "article" => "serial_part",
          "software" => "online",
          "unpublished" => "online",
          "dataset" => "online",
          "website" => "webdoc",
          "webresource" => "webdoc",
          "webpage" => "online",
          "online" => "online",
        }.freeze

        DEFAULT_KIND = "report"

        class << self
          def mapped?(type)
            TO_KIND.key?(type.to_s)
          end
        end

        def self.kind_for(type)
          TO_KIND.fetch(type.to_s, DEFAULT_KIND)
        end
      end
    end
  end
end
