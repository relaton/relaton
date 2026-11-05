# relaton-cli ships in lockstep with the combined `relaton` gem, so its version
# is that gem's version — the single source of truth in Relaton::VERSION. relaton
# is a hard runtime dependency, so requiring its lightweight version file always
# resolves. Don't hardcode a string here; it would silently drift on a bump.
#
# Defined with const_set on purpose: a `VERSION = Relaton::VERSION` line
# matches the release workflow's version-file heuristic (`^VERSION =`),
# which sorts this file ahead of lib/relaton/version.rb and hands
# gem-release a re-export it cannot read — the 2026-11-05 release dispatch
# aborted exactly there ("Could not determine current version").
require "relaton/version"

module Relaton
  module Cli
    const_set :VERSION, Relaton::VERSION
  end
end
