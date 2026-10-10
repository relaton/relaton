# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The rawbib fixture expectations reconcile against pubid 2.0.0.pre.alpha.21
# (the stage-word faces: "-YYYY-MM" dates, the D= designator, the glued
# "/V<n>" iteration, pubid#203). Pin the exact tested release until pubid
# 2.0 final; the gemspec floor follows.
gem "pubid", "2.0.0.pre.alpha.21"

# Default group (installed even when the release strips dev/test): the release
# job runs `bundle config without 'development test'` before `bundle exec rake
# build_all`, so rake must live outside those groups or publishing can't run it.
gem "rake"

group :development, :test do
  # XML/YAML canonical comparison matchers for specs. Pinned below 0.3.52:
  # that version adds a dependency on `yeptris`, and `lutaml-model` then picks
  # yeptris as its YAML adapter. Its first model `to_yaml` requires
  # `yeptris/psych`, which replaces `Object#to_yaml` for the whole process. The
  # `---` header is then lost on Linux, and on Windows every `to_yaml` raises
  # `NameError: uninitialized constant Yeptris::FFI::NODE_SCALAR`. Remove the
  # pin when yeptris no longer replaces `Object#to_yaml`.
  gem "canon", "< 0.3.52"
  gem "equivalent-xml"
  gem "pry"            # bin/console
  gem "rspec"
  gem "rspec-command"  # relaton-cli acceptance specs
  gem "rspec-html"     # relaton-cli
  gem "ruby-jing"      # RelaxNG schema validation
  gem "simplecov"
  gem "timecop"
  gem "vcr"
  gem "webmock"
  gem "webrick"
end



# leptris floor: moxml 0.5.120 absorbed the #335/#347 foreign-child
# handling; 1.9.333 is the current published line.
gem "leptris", ">= 1.9.331"
# 0.5.120 gates every foreign child kind through the #335 rebuild
# machinery before the C add (moxml#347, verified on the published
# 0.5.120 gem) — relaton#254
gem "moxml", ">= 0.5.120"
