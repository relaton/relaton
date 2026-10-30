require "relaton/logger"

module Relaton
  # Registered here as well as in the root entry: flavor files and their
  # specs load directly via require "relaton/<flavor>", never through
  # relaton.rb, and the boundary parsers need this constant either way.
  autoload :Json, "relaton/json"
end
require_relative "version"
require_relative "core/request_error"
require_relative "core/array_wrapper"
require_relative "core/hash_keys_sybolizer"
require_relative "core/date_parser"
require_relative "core/processor"
require_relative "core/data_fetcher"
require_relative "core/hit_collection"
require_relative "core/workers_pool"
require_relative "core/pacer"
require_relative "core/governor"
