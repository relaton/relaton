require "yeptris"

module Relaton
  # JSON at the system boundary — data we do not control. Everything we
  # generate or own (index manifests, shards, the db cache, request bodies,
  # the schema-version table) parses with Yeptris::JSON's default strict
  # surface.
  module Json
    module_function

    # Third-party feeds carry duplicate keys in the wild (Crossref book
    # records keyed by ISBN, NIST's scraped pubs export keyed by "&nbsp",
    # the UN search API's blank keys, CCSDS's embedded config); parsing them
    # the historical way is last-wins. yeptris 0.6.51 carries the boundary
    # opt-out (yeptris-ruby#335/#339), so the whole stack stays on yeptris —
    # no stdlib fallback anywhere.
    def parse_external(source)
      ::Yeptris::JSON.load(source, allow_duplicate_key: true)
    end
  end
end
