# The relaton-cli gem is a compatibility shell: the CLI implementation
# lives in the relaton gem (lib/relaton/cli). Requiring this gem just
# pulls relaton, which provides every `relaton/cli` and `relaton-cli`
# entry point the standalone gem used to ship.
require "relaton"
