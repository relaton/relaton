module Relaton
  module Cli
    # The `--api` option of `fetch` and `collection fetch` (relaton#535).
    # Here, not in command.rb: a command's class body reads it.
    API_OPTION_DESC = "Ask api.relaton.org before the flavor's own " \
                      "source; --no-api does not (default: RELATON_USE_API, " \
                      "else off)".freeze

    module Util
      extend Relaton::Bib::Util
      PROGNAME = "relaton-cli".freeze
    end
  end
end
