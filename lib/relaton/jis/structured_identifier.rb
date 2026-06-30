# frozen_string_literal: true

module Relaton
  module Jis
    class StructuredIdentifier < Iso::StructuredIdentifier
      def to_all_parts!
        super
        pn = project_number
        pn.content = "#{pn.content} (all parts)" if pn&.content
      end
    end
  end
end
