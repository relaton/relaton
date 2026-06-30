# frozen_string_literal: true

# Usage:
#
# Adapted from pubid's monorepo_importer.rb for the relaton monorepo.
#
# Import each relaton-* gem into the monorepo as a git subtree under
# gems/<gem-name>/. Idempotent: if the directory exists, `git subtree pull`
# updates it; otherwise `git subtree add` creates it.
#
# Branch resolution per gem:
#   - if SOURCE_BRANCH is set, use it (must exist or the gem is skipped)
#   - else: prefer "lutaml-integration", fall back to the monorepo's current
#     branch ("main" by default).
#
# Run:
#   ruby monorepo_importer.rb              # all gems
#   ruby monorepo_importer.rb relaton-iso  # one gem
#   SOURCE_BRANCH=main ruby monorepo_importer.rb relaton-iso  # explicit branch
#
# After import, verify with:
#   git log gems/<gem>/  # shows the subtree-add merge commit
#   git blame -C gems/<gem>/<some_file>  # traces through the merge

require "fileutils"

# All 33 relaton-* gems imported from individual GitHub repos.
# `relaton` itself is handled separately via RENAMED below — its upstream
# GH repo is named `relaton-db` (the result of an upstream rename).
GEMS = %w[
  relaton-core
  relaton-index
  relaton-logger
  relaton-bib
  relaton-3gpp
  relaton-bipm
  relaton-bsi
  relaton-calconnect
  relaton-ccsds
  relaton-cen
  relaton-cie
  relaton-doi
  relaton-ecma
  relaton-etsi
  relaton-gb
  relaton-iana
  relaton-iec
  relaton-ieee
  relaton-ietf
  relaton-iho
  relaton-isbn
  relaton-iso
  relaton-itu
  relaton-jis
  relaton-nist
  relaton-oasis
  relaton-ogc
  relaton-oiml
  relaton-omg
  relaton-plateau
  relaton-un
  relaton-w3c
  relaton-xsf
  relaton-cli
].freeze

# The `relaton` gem lives in `gems/relaton/` locally but its upstream GH
# repo is named `relaton-db` (renamed upstream). Re-importing is supported.
RENAMED = { "relaton" => "relaton-db" }.freeze

ORG = "relaton"
PREFERRED_BRANCH = "lutaml-integration"
DEFAULT_BRANCH = `git rev-parse --abbrev-ref HEAD`.strip
DEFAULT_BRANCH = "main" if DEFAULT_BRANCH.empty?

def remote_url(gem_name)
  upstream = RENAMED[gem_name] || gem_name
  "https://github.com/#{ORG}/#{upstream}.git"
end

def remote_branches(url)
  output = `git ls-remote --heads #{url} 2>/dev/null`
  output.lines.map { |l| l.split.last.sub("refs/heads/", "") }
end

def resolve_branch(gem_name, override)
  url = remote_url(gem_name)
  branches = remote_branches(url)
  return nil if branches.empty?
  return override if override && branches.include?(override)
  return PREFERRED_BRANCH if branches.include?(PREFERRED_BRANCH)
  return DEFAULT_BRANCH if branches.include?(DEFAULT_BRANCH)
  return "main" if branches.include?("main")
  branches.first
end

def import_gem(gem_name, override_branch = nil)
  prefix = "gems/#{gem_name}"
  url = remote_url(gem_name)
  branch = resolve_branch(gem_name, override_branch)

  unless branch
    warn "✗ #{gem_name}: no branches found at #{url}, skipping"
    return false
  end

  msg = "Pulled subtree for #{gem_name} from #{branch}"

  if Dir.exist?(prefix)
    puts "↻ #{gem_name}: pulling #{branch} into existing #{prefix}/"
    ok = system("git subtree pull --prefix=#{prefix} #{url} #{branch} -m '#{msg}'")
    unless ok
      warn "✗ #{gem_name}: subtree pull failed; resolve conflicts manually"
      return false
    end
  else
    puts "+ #{gem_name}: adding subtree from #{branch} at #{prefix}/"
    ok = system("git subtree add --prefix=#{prefix} #{url} #{branch}")
    unless ok
      warn "✗ #{gem_name}: subtree add failed"
      return false
    end
  end
  true
end

requested = ARGV.empty? ? GEMS : ARGV
override = ENV["SOURCE_BRANCH"]

failures = []
requested.each do |g|
  unless GEMS.include?(g) || RENAMED.key?(g)
    warn "✗ #{g}: not in known gem list, skipping"
    failures << g
    next
  end
  failures << g unless import_gem(g, override)
end

puts ""
if failures.empty?
  puts "✓ All #{requested.size} gem(s) imported on branch '#{DEFAULT_BRANCH}'."
else
  puts "⚠ #{failures.size} gem(s) failed: #{failures.join(', ')}"
  exit 1
end
