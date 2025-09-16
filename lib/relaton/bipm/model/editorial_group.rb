require_relative "committee"
require_relative "workgroup"

module Relaton
  module Bipm
    class EditorialGroup < Lutaml::Model::Serializable
      choice do
        attribute :committee, Committee, collection: (1..)
        attribute :workgroup, WorkGroup, collection: true
      end

      xml do
        map_element "committee", to: :committee, with: { from: :committee_from_xml }
        map_element "workgroup", to: :workgroup
      end

      # This is needed to properly parse old XMLs where committee has variants
      def committee_from_xml(model, value)
        model.committee = value.each_with_object([]) do |cmt, acc|
          vars = cmt.children.each_with_object([]) do |var, acc2|
            next unless var.name == "variant"

            acc2 << Committee.new(
              content: var.text, acronym: cmt["acronym"], language: var["language"], script: var["script"]
            )
          end

          acc.concat vars
          next if vars.any?

          acc << Committee.from_xml(cmt.to_xml)
        end
      end
    end
  end
end
