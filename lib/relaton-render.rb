# frozen_string_literal: true

require "relaton/render/version"
require "relaton/render/iso690"

module Relaton
  module Render
    # A bibliographic item whose style template resolves to nothing: the
    # single-item API raises, the batch API skips
    class Unrenderable < StandardError; end

  end
end
