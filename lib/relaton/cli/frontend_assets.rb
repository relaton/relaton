module Relaton
  module Cli
    # Resolves the compiled frontend bundle (`app.iife.js` + `style.css`) whose
    # source lives at `lib/relaton/cli/frontend/` and whose built dist is
    # committed inside the gem under `frontend/dist/`. Both the installed gem
    # and a git checkout place `frontend/dist` at the gem root, so one relative
    # path covers both.
    #
    # If the bundle is missing (a fresh checkout that hasn't run the frontend
    # build), raise a clear, actionable error rather than emitting a broken page.
    module FrontendAssets
      class BuildMissingError < StandardError; end

      # gem root = up three from lib/relaton/cli
      DEFAULT_DIST = File.expand_path("frontend/dist", __dir__).freeze

      class << self
        # Overridable so specs can point at a fixture dist without a Node build.
        attr_writer :dist_dir

        def dist_dir
          @dist_dir || DEFAULT_DIST
        end

        # Run a block with a temporary dist dir, restoring the previous one.
        def with_dist_dir(dir)
          previous = @dist_dir
          @dist_dir = dir
          yield
        ensure
          @dist_dir = previous
        end

        def iife
          read("app.iife.js")
        end

        def stylesheet
          read("style.css")
        end

        def built?
          File.exist?(File.join(dist_dir, "app.iife.js"))
        end

        def read(name)
          path = File.join(dist_dir, name)
          unless File.exist?(path)
            raise BuildMissingError,
                  "Frontend build missing (#{name} not found in #{dist_dir}). " \
                  "Run `bundle exec rake spec:build_frontend` at the repo root " \
                  "(or `cd lib/relaton/cli/frontend && npm install && npm run build`) first."
          end
          File.read(path, encoding: "utf-8")
        end
      end
    end
  end
end
