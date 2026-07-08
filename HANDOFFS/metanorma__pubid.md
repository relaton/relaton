# Hand-off: add a uniform "owned prefixes" API to `pubid`

> **STATUS: IMPLEMENTED.** Delivered in the pubid worktree
> `/work/metanorma/pubid/.claude/worktrees/feat/flavor-prefixes-api` as
> `Pubid.prefixes(flavor)`, `Pubid.prefix_flavors`, and the `Pubid::PrefixesSupport`
> mixin (per-flavor `PREFIXES` + central `Pubid::JOINT_PREFIXES`). relaton now
> consumes `Pubid::<Flavor>.prefixes`. **Remaining:** pubid must commit + release a
> version carrying this API, then relaton bumps its gemspec `pubid` pin to it and
> drops the temporary `path:` override in the Gemfile. This file is kept for
> historical context.

**Target project:** `/work/metanorma/pubid` (the `pubid` gem, unified per-SDO
identifier library; installed here as `pubid 2.0.0.pre.alpha.5`).

**Run it in a separate session:**
`cd /work/metanorma/pubid` then `cw "<paste this whole file>"`.

---

## Why

`relaton` (relaton/relaton PR #21, issue relaton-db#103) is building a **global
prefix register** — a map from an SDO document-ID prefix (e.g. `"ISO"`,
`"ISO/IEC"`, `"NIST"`, `"DD"`) to the flavor(s) that own it, used to route a
reference string to the right backend.

Right now relaton **hand-codes** each flavor's prefix list in its processors
(`@prefixes = ["ISO", "ISO/IEC", …]`). The maintainer's review feedback
(@ronaldtse) is that this ownership knowledge should come **from pubid**, the
source of truth for each SDO's identifier grammar — because pubid already knows
the non-obvious prefixes (his example: **BSI owns `DD`**), and hand-coding will
drift from what pubid's parser actually accepts.

The blocker: **pubid currently exposes no uniform, public way to enumerate a
flavor's prefixes.** Verified at runtime against `2.0.0.pre.alpha.5`:

- `Pubid.prefixes` — does not exist.
- `Pubid::Registry.flavor_names` — returns `[]` until a flavor is parsed.
- ISO: `Pubid::Iso::Parser::ORGANIZATIONS` exists (but it's the *copublisher*
  org list, not the owned leading prefixes).
- IEC: `Pubid::Iec::Components::Publisher::PUBLISHERS` keys exist
  (`["IEC","ISO/IEC","CISPR","IECEE","IECEx","IECQ"]`).
- IEEE: `Pubid::Ieee::PreParser::PUBLISHERS` is a **private constant**
  (`NameError` when referenced).
- NIST: `Pubid::Nist.configuration.all_series_codes` **raises**
  `ConfigurationError` (series file path bug in this build).
- BSI: prefixes (`DD`, `PD`, `BS`, …) live only inside the Parslet grammar — no
  constant at all.

The shapes are inconsistent, some are private, one is broken. Relaton should not
reach into these internals. **Please add a stable, uniform public API.**

## What to add

A per-flavor class method returning the set of **leading identifier prefix
tokens** that flavor recognizes — i.e. the tokens a printed identifier can
*start with* such that the string belongs to this SDO. This is exactly the
routing key relaton needs (`"DD 1234"` → BSI, `"ISO/IEC 8802" → ISO & IEC`).

```ruby
Pubid::Iso.prefixes
# => ["ISO", "ISO/IEC", "IEC/ISO", "ISO/IEC/IEEE", ...]

Pubid::Iec.prefixes
# => ["IEC", "ISO/IEC", "IEC/ISO", "CISPR", "IECEE", "IECEx", "IECQ", ...]

Pubid::Nist.prefixes
# => ["NIST", "NBS", ...]   # plus FIPS etc. if those route to NIST

Pubid::Bsi.prefixes
# => ["BS", "BSI", "DD", "PD", "PAS", "NA", "TS", "HB", "BS ISO", "BS EN", ...]

Pubid::Ieee.prefixes
# => ["IEEE", "AIEE", "ANSI/IEEE", ...]
```

### Required semantics
- **Static** — callable without parsing a specific identifier string (relaton
  registers these at startup, before it has any reference in hand).
- **Uniform** — the same method name and a plain `Array<String>` return for
  **every** registered flavor, so a consumer can iterate flavors generically.
- **Joint publications appear symmetrically** — a co-published prefix must be
  listed by **every** co-publisher. `"ISO/IEC"` ∈ `Pubid::Iso.prefixes` **and**
  `Pubid::Iec.prefixes`; `"ISO/IEC/IEEE"` ∈ all three of Iso/Iec/Ieee. This is
  what lets relaton return `[Iso, Iec]` for `"ISO/IEC"`.
- **Case/whitespace** — return canonical strings as printed
  (e.g. `"BS EN ISO"`, `"ISO/IEC"`); consumers fold case themselves.
- Sourced from the grammar/config the parser already uses — **not** a new
  hand-maintained list that can drift from the parser.

### Nice-to-have (optional)
A top-level convenience:
```ruby
Pubid.prefixes(:iso)          # delegates to Pubid::Iso.prefixes
Pubid.prefix_flavors          # => { "ISO" => [:iso], "ISO/IEC" => [:iso, :iec], ... }
```
`prefix_flavors` would let relaton drop its own aggregation loop entirely, but
the per-flavor `.prefixes` method is the essential deliverable.

### Please also decide & document one semantic question
Should **series/type tokens** (NIST `SP`/`FIPS`/`TN`, BSI `DD`/`PD`) be included?
- Relaton needs any leading token that should route to the flavor, so **yes**
  for tokens that begin a reference (BSI `DD 1234`, NIST `FIPS 140`).
- But pure sub-series that never appear without the publisher prefix should be
  excluded to avoid false routing.
Whichever you choose, document it in the method's YARD so relaton can rely on it.

## Consumer side (for context — relaton will do this, no action needed here)

Once released, relaton's `Core::Processor#prefixes` will derive from pubid, e.g.
each flavor processor maps its `@short`/pubid-flavor and calls
`Pubid::<Flavor>.prefixes`, replacing the interim hand-coded `@prefixes` lists.
Relaton pins `pubid` in its gemspec (`~> 2.0.0.pre.alpha.5`), so this needs a
pubid release and a relaton bump.

## Acceptance
- `Pubid::Iso.prefixes`, `Pubid::Iec.prefixes`, `Pubid::Nist.prefixes`,
  `Pubid::Bsi.prefixes`, `Pubid::Ieee.prefixes` (at minimum) each return a
  non-empty `Array<String>` with no parsing required.
- BSI's list includes `"DD"` and `"PD"`; IEC's includes `"ISO/IEC"`; ISO's
  includes `"ISO/IEC"` and `"ISO/IEC/IEEE"`; IEEE's includes `"ISO/IEC/IEEE"`.
- Specs cover the joint-publication symmetry (same string in each co-publisher's
  list) and the static (no-parse) call path.
- YARD documents the series/type-token inclusion decision.
