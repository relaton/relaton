require "json"

module Relaton
  # JSON at the system boundary — data we do not control. Everything we
  # generate or own (index manifests, shards, the db cache, request bodies,
  # the schema-version table) parses with Yeptris::JSON, whose duplicate-key
  # contract tracks JSON::VERSION.
  module Json
    module_function

    # Third-party feeds carry duplicate keys in the wild (Crossref book
    # records keyed by ISBN, NIST's scraped pubs export keyed by "&nbsp",
    # the UN search API's blank keys, CCSDS's embedded config); parsing them
    # the historical way is last-wins. Under json >= 3 both JSON.parse and
    # yeptris reject duplicates by default, so the lenient contract has to be
    # stated here rather than inherited from the parser.
    def parse_external(source)
      ::JSON.parse(source, allow_duplicate_key: true)
    end
  end
end
