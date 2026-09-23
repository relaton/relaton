# The per-flavor `autoload` lines live in `relaton.rb`, not `relaton/db`.
# `index_name_for`/`pubid_class_for` resolve `Relaton::<Flavor>::INDEXFILE`, so
# without the umbrella every `--pubid-flavor` fails with "no relaton flavor".
# Declaring autoloads is cheap: no flavor is loaded until it is referenced.
require "relaton"
require "relaton/db"

module Relaton
  module Cli
  end
end

require_relative "relaton/bibcollection"
require_relative "relaton/bibdata"
require_relative "relaton/element_finder"
require_relative "relaton/cli/yaml_convertor"
require_relative "relaton/cli"