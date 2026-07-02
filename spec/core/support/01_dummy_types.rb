require "forwardable"


# module Pubid::Core
#   class BaseTestIdentifier < Identifier::Base

#     # @overload parse() not to invoke real parser
#     def self.parse(_id)
#       # always return "ISO 1" instance for any provided string
#       new(publisher: "ISO", number: 1)
#     end

#     def to_s
#       "#{@publisher} #{@number}"
#     end
#   end
# end

# module Relaton::Core
#   class DummyDataFetcher < DataFetcher
#     INDEX_TYPE = "ISO"
#     INDEX_FILE = "index-v1.yaml"

#     def self.get_identifier_class
#       Pubid::Core::BaseTestIdentifier
#     end
#   end
# end
