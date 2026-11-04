# The relaton-render gem is a compatibility shell: the citation renderer
# lives in the relaton gem (lib/relaton/render). Requiring this gem just
# pulls relaton, which provides every `relaton/render` entry point the
# standalone gem used to ship.
require "relaton"
