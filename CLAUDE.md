# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Monorepo for the Relaton family of Ruby gems (bibliographic references to technical standards). 34 gems live under `gems/<name>/`, each a normal Ruby gem with its own `Gemfile`, `Rakefile`, gemspec, and `spec/`. `README.adoc` is the canonical user-facing overview; this file captures the non-obvious bits for working in the repo.

Origin: `https://github.com/relaton/relaton`. The upstream `relaton/relaton-db` GH repo holds the history of the main `relaton` gem (the renaming happened upstream); it pulls into `gems/relaton/` here via `monorepo_importer.rb`'s `RENAMED` map.

## Common commands

```sh
bundle install
bundle exec rake test:all                       # every gem's specs (continues past failures, prints summary)
bundle exec rake test:relaton_iso               # one gem (gem name with - → _)
bundle exec rake test:failed                    # re-run only previously failed specs (filters by .rspec_status)
bundle exec rake test:failed:relaton_iso        # re-run the next failing spec for one gem
bundle exec rake version:show                   # master + per-gem versions
bundle exec rake version:check                  # enforce shared MAJOR.MINOR across all gems
bundle exec rake "version:bump[minor]"          # bump master MAJOR.MINOR, sync to all gems (resets PATCH to 0)
bundle exec rake "version:bump_patch[relaton-iso]"  # bump one gem's PATCH only
bundle exec rake release:show_order             # release-order.json contents
bundle exec rake release:validate_order         # every gem in gems/ is in release-order.json (and vice versa)
bundle exec rake -T                             # all tasks
```

Per-gem work (each gem is self-contained):

```sh
cd gems/relaton-iso
rm -f Gemfile.lock && bundle && bundle exec rake
```

Per-gem `Gemfile`s pin cross-gem deps via `path: "../<sibling>"`, so edits in one gem are picked up immediately in another without reinstall. `test:all` runs each gem in `Bundler.with_unbundled_env` and removes the per-gem `Gemfile.lock` first.

## Architecture: what's non-obvious

**Namespace move (no back-compat aliases).** The original top-level `relaton` gem kept its name but had its classes moved under `Relaton::Db::*` (`Relaton::Db::Cache`, `Relaton::Db::Registry`, `Relaton::Db::Configuration`, `Relaton::Db::WorkersPool`, `Relaton::Db::Util`, `Relaton::Db::VERSION`, `Relaton::Db.configure`). `Relaton::Db` itself (the main DB class) is unchanged. There are intentionally no aliases — downstream code must update. Don't add back-compat shims.

**Registry load order.** `Relaton::Db::Registry` requires each flavor gem's top-level (`b`) before its `b/processor` so the flavor's `util.rb` is loaded first. If you add a flavor processor, mirror that pattern — loading the processor first will blow up.

**`relaton` is the central gem AND the umbrella.** `gems/relaton/` ships the `Relaton::Db` API (registry, cache, workers pool) and *also* declares runtime deps on every flavor plugin (pinned `~> 2.2.0.pre.alpha.1` during the current prerelease window — see Versioning model), so `gem install relaton` gives users a working multi-flavor setup out of the box. `relaton-cli` is intentionally NOT a runtime dependency. There is no separate `relaton-db` gem — it was briefly split out, then merged back.

**Versioning model.** Master `MAJOR.MINOR` lives in `lib/relaton/version.rb` as `Relaton::MONOREPO_VERSION` (currently `2.2.0.pre.alpha.1`). All gems share the same `MAJOR.MINOR` but carry independent `PATCH` numbers; inter-gem deps are pinned `~> MAJOR.MINOR.0` so PATCH can drift per gem without churn. The `MAJOR.MINOR.0` floor must be re-bumped in the same commit as a master `version:bump`. `version:sync` resets every gem to the master (PATCH → 0) — only use it when intentionally aligning patches after a master bump.

**Prerelease window (2.2.0 alpha).** The 2.2.0 line is currently shipping as `2.2.0.pre.alpha.N` prereleases (it depends on the `pubid 2.0.0.pre.alpha.3` prerelease). While in this window, every gem's version is the alpha string and inter-gem deps are pinned `~> 2.2.0.pre.alpha.1` (a prerelease sorts *below* its release, so a plain `~> 2.2.0` would not resolve sibling alphas; the alpha pin admits both the alphas and the eventual 2.2.x stable). When cutting stable 2.2.0, sync versions to `2.2.0` and revert the inter-gem pins to `~> 2.2.0`. Alpha releases go out via the `release` workflow in `skip` mode (it builds + `gem push`es the current versions from `main`; no tag/GitHub Release).

**Per-gem version file paths follow Ruby module conventions.** `gems/relaton-iso/lib/relaton/iso/version.rb`. The 3gpp gem is the special case: directory is `gems/relaton-3gpp/lib/relaton/3gpp/`, but Ruby module is `Relaton::ThreeGpp`.

**release-order.json drives the release workflow.** Dep-aware order: logger → core → index → bib → flavor plugins (alpha, ISO-independent first) → ISO-dependent flavors (bsi, gb, iec, jis, ogc, plateau) → doi → relaton → cli. The `release` GH workflow walks this list. `rake release:validate_order` enforces it covers `gems/` exactly. `relaton` releases after every flavor (it depends on all of them) and before `relaton-cli` (which now depends on `relaton`).

**`monorepo_importer.rb` is idempotent.** Re-running calls `git subtree pull` for existing dirs and `git subtree add` for new ones. Branch resolution prefers `lutaml-integration`, falls back to the monorepo's current branch, then `main`, then whatever's first. Override with `SOURCE_BRANCH=<name>`. The `relaton` gem is the special case: its upstream GH repo is named `relaton-db` (via the `RENAMED` map).

**History across subtree imports.** File history follows through the import commit; use `git log --follow -- gems/<gem>/path/to/file.rb` and `git blame -CCC gems/<gem>/<file>`. Don't expect linear history — each gem joined via a subtree merge commit.

## Conventions to keep

- Don't add backward-compat aliases for the `Relaton::Db::*` rename — clean break is intentional.
- Don't add `relaton-cli` as a runtime dep of `relaton`.
- Don't re-split `relaton-db` out of `relaton`; the merged-single-gem shape is intentional (matches v2.1).
- Cross-gem deps in per-gem `Gemfile`s use `path: "../<sibling>"`, not git refs or version constraints.
- When adding a brand-new gem: append to `monorepo_importer.rb`'s `GEMS` list AND insert into `release-order.json` at the dep-correct position.
- Scratch/one-off scripts go under `/tmp/`, not the project root.
