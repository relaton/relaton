# relaton-render ships in lockstep with the combined `relaton` gem, so its
# version is that gem's version — the single source of truth in
# Relaton::VERSION. Defined with const_set on purpose: a `VERSION = ...`
# line here matches the release workflow's version-file heuristic, which
# would hand gem-release this file instead of lib/relaton/version.rb —
# a re-export it cannot read (cli's) or a stale literal it would bump
# instead of the gem (this one, which froze at the standalone 3.0.0).
require "relaton/version"

module Relaton
  module Render
    const_set :VERSION, Relaton::VERSION
  end
end
