# Cassette replay must not wait out the crawl's request pacer (see
# Relaton::W3c::SafeRealize.gap). Set before the flavor loads, so the
# module-level pacer is built with no gap, and re-read on every reset!.
ENV["RELATON_W3C_GAP"] ||= "0"
