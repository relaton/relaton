# relaton-cli ships in lockstep with the combined `relaton` gem, so its version
# is that gem's version — the single source of truth in Relaton::VERSION. relaton
# is a hard runtime dependency, so requiring its lightweight version file always
# resolves. Don't hardcode a string here; it would silently drift on a bump.
require "relaton/version"

module Relaton
  module Cli
    VERSION = Relaton::VERSION
  end
end
