# frozen_string_literal: true

require_relative "endnote/from_endnote"
require_relative "endnote/to_endnote"

module Relaton
  module Bib
    module Converter
      module Endnote
        # Refer-format field tags (the EndNote "tagged format"): one
        # `%X value` line per field, records separated by a blank line.
        TAGS = {
          author: "%A", title: "%T", date: "%D", publisher: "%I",
          edition: "%@", keyword: "%K", url: "%U", journal: "%J",
          series: "%S",
        }.freeze

        # ItemData -> Refer string
        def self.from_item(item)
          ToEndnote.new(item).to_s
        end

        # Refer string -> Hash{String=>ItemData}
        def self.to_item(refer_str)
          FromEndnote.parse(refer_str)
        end
      end
    end
  end
end
