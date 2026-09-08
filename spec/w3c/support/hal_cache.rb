# `W3cApi::Hal` is a Singleton that memoizes ONE `Lutaml::Hal::ModelRegister`
# with an in-memory URL cache, and registers it in the `Lutaml::Hal::GlobalRegister`
# Singleton. `W3cApi::Client.new` holds no state of its own, so a fresh client
# per example still reads that one process-wide cache.
#
# Left warm, the cache turns the suite into a chain: `DataParser#parse` realizes
# `@spec.links.specification` for the `editionOf` relation, so the
# `vcr: "webrtc-20241008"` examples fetch `https://api.w3.org/specifications/webrtc`
# and leave it cached for the later `vcr: "webrtc"` examples, which then issue no
# request at all. A cassette recorded in that state records only what was missing
# from the cache, and replays only in that one example order — which is how
# `webrtc.yml` came to lack the very request its own examples make. The failure
# surfaces far from its cause: any earlier example that raises leaves the cache
# cold, and three unrelated examples die with `UnhandledHTTPRequestError`.
#
# Clearing between examples makes each one issue its own requests, so a cassette
# records what its examples actually need.
#
# `clear_all_caches` delegates to each register's `clear_cache`, a no-op when no
# register has a cache manager, so this is safe before any client is built. The
# constant is read lazily because `spec/spec_helper.rb` loads `support/` before
# the flavor.
RSpec.configure do |config|
  config.before do
    if defined?(::Lutaml::Hal::GlobalRegister)
      ::Lutaml::Hal::GlobalRegister.instance.clear_all_caches
    end
  end
end
