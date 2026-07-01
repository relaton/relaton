# frozen_string_literal: true

# Shared SimpleCov setup. Every flavor suite runs from its own spec/<flavor>/
# dir (via `cd spec/<flavor> && rspec`), so left to its defaults SimpleCov roots
# itself at that spec dir — putting lib/ outside the root (untracked) and making
# `add_filter "/spec/"` miss the specs (their path relative to spec/<flavor>/ has
# no "/spec/"). The report then shows spec files, not the code.
#
# Here we force a single repo-root-rooted, shared report: all flavors write to
# one coverage/ dir under a unique command_name, so their results MERGE into one
# coverage/index.html covering the whole lib/ tree.
require "simplecov"

repo_root = File.expand_path("..", __dir__) # spec/ -> repo root

SimpleCov.root repo_root
SimpleCov.coverage_dir File.join(repo_root, "coverage")
# CWD is spec/<flavor>/ — unique per flavor, so sequential runs merge, not clobber.
SimpleCov.command_name "spec:#{File.basename(Dir.pwd)}"

SimpleCov.start do
  # Whole suite can exceed the 10-min default; keep early flavors in the merge.
  merge_timeout 3600
  add_filter %r{/spec/}
  # Report every lib file, even ones a given flavor never loads (0% until some
  # flavor exercises them); the merge takes the best coverage across flavors.
  track_files "#{repo_root}/lib/**/*.rb"
end
