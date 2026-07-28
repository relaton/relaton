# frozen_string_literal: true

# Relaton::Sdo — the standards-body organization & logo store (metanorma#346,
# relaton-db#132). A NON-flavor, lazily-autoloaded top-level component: it has
# no processor and no Db::Registry entry. It fetches a small `index.yaml`
# manifest published by the `relaton-data-sdo` data repo, caches it under
# `~/.relaton/sdo/`, and exposes org names/translations and logo variants
# (differentiated by style/format/size) via `Relaton.organization`.

require "net/http"
require "uri"
require "yaml"
require "base64"
require "fileutils"
require "singleton"

require_relative "index/file_storage"
require_relative "sdo/config"
require_relative "sdo/name"
require_relative "sdo/logo"
require_relative "sdo/organization"
require_relative "sdo/fetcher"
require_relative "sdo/store"

module Relaton
  module Sdo
    class Error < StandardError; end
  end
end
