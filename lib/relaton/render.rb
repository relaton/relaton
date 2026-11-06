# frozen_string_literal: true

# The rendering surface of the consolidated gem — the `relaton/render`
# entry the standalone relaton-render gem served as its primary require
# path. `require "relaton-render"` (the hyphen umbrella in
# lib/relaton-render.rb) resolves to this same surface: one gem ships
# both codebases, so both spellings must keep working, and neither may
# fall through to a still-bundled retired gem.
require_relative "render/iso690"

module Relaton
  module Render
    # A bibliographic item whose style template resolves to nothing: the
    # single-item API raises, the batch API skips
    class Unrenderable < StandardError; end
  end
end
