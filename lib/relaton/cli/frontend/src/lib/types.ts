/** One contributor (author, publisher, editor, …) on the detail page. */
export interface Contributor {
  name: string;
  role?: string | null;
}

/** One of a document's identifiers (may repeat per language / scheme). */
export interface DocIdentifier {
  id: string;
  type?: string | null;
  language?: string | null;
}

// One related document, e.g. { type: "obsoletedBy", id: "ISO 29862:2024" }.
// Only the target's DocID is carried — no title or date — because the id is both
// the label and the key the detail page matches against the rest of the corpus
// to decide whether it can be rendered as an intra-dataset link.
export interface Relation {
  type?: string | null;
  id: string;
}

/** One dated event, e.g. { type: "published", value: "2009-06-19" }. */
export interface DocDate {
  type?: string | null;
  value: string;
}

// One bibliographic document as rendered in the index. This shape is the
// contract shared with the Ruby side (Relaton::Cli::IndexItemNormalizer):
// whatever the generator emits as JSON must map here.
//
// The first block is the summary contract, carried by the `search-NNNN.json`
// shards and loaded progressively. The second block holds the richer detail
// fields, which live in the separate `detail-NNNN.json` shards and are fetched
// only when a detail panel opens — so they are absent until then, and stay
// absent for a document that has none.
export interface IndexDocument {
  /** Primary rendered Relaton DocID, e.g. "BIPM CCRI 21 (2009)". */
  id: string;
  /** Main title (English preferred). */
  title: string;
  /** Document type, e.g. "meeting-report" (from ext.doctype). */
  doctype: string | null;
  /** Workflow stage, e.g. "published". */
  stage: string | null;
  /** Publication date, ISO "YYYY-MM-DD". */
  date: string | null;
  /** Human-facing landing/link URL, if any. */
  link: string | null;
  /** URL (or relative path) to the raw Relaton YAML source. */
  yaml: string | null;

  // Assigned by the shard loader, NOT emitted by the generator: this document's
  // position in the full corpus, which is what addresses its detail shard. It is
  // carried explicitly rather than derived from the array index because a shard
  // that fails to load leaves a hole — every later document would then sit at a
  // lower index than its true position and resolve to the wrong detail shard.
  pos?: number;

  /** Abstract / summary text (HTML stripped). */
  abstract?: string | null;
  /** Edition, e.g. "2". */
  edition?: string | null;
  /** Language codes, e.g. ["en", "fr"]. */
  languages?: string[];
  /** Subject keywords. */
  keywords?: string[];
  /** Publishing organization name. */
  publisher?: string | null;
  /** All contributors with their roles. */
  contributors?: Contributor[];
  /** All identifiers (multilingual/scheme variants of `id`). */
  docids?: DocIdentifier[];
  /** All dated events. */
  dates?: DocDate[];
  /** Related documents (obsoletes, updatedBy, partOf, …). */
  relations?: Relation[];
}

export interface IndexData {
  title: string;
  /** Site blurb shown as the header subtitle (optional; also the meta description). */
  description?: string | null;
  documents: IndexDocument[];
  /** ISO timestamp the site was generated (optional, for the footer). */
  generated?: string | null;
}

/** Compact record shape carried by the `search-NNNN.json` summary shards. */
export interface CompactRecord {
  r: string; // reference / id
  c: string; // content / title
  t?: string | null; // doctype
  s?: string | null; // stage
  d?: string | null; // date
  u?: string | null; // url (yaml)
  l?: string | null; // link
}

// One entry in a `detail-NNNN.json` shard: the fields the summary record does
// NOT carry, tagged with `r` (the document id) so a positional lookup can be
// verified before its fields are shown. A shard slot is `null` when the
// document at that position has no detail fields at all — the slot is still
// written, so position stays aligned with the summary shards.
export type DetailRecord = Pick<
  IndexDocument,
  | "abstract"
  | "edition"
  | "languages"
  | "keywords"
  | "publisher"
  | "contributors"
  | "docids"
  | "dates"
  | "relations"
> & { r: string };

// The shard layout, read from the mount node's data-* attributes. There is
// deliberately no manifest file: these five scalars are everything the frontend
// needs, and carrying them inline saves a round-trip before the first shard can
// be requested (and a failure mode where the manifest 404s but the shards are
// fine). Shard file names are derived by convention — `search-0000.json`,
// `detail-0000.json` — and resolve relative to the page, which sits beside them.
export interface ShardInfo {
  /** Documents across the whole corpus. */
  total: number;
  /** Number of `search-NNNN.json` files. */
  shards: number;
  /** Summary records per shard (the last one may hold fewer). */
  shardSize: number;
  /** Number of `detail-NNNN.json` files; 0 when built with --no-detail. */
  detailShards: number;
  /** Detail slots per shard — the divisor for the positional lookup. */
  detailShardSize: number;
}

// Progressive-load state shared with App. A plain reactive object rather than a
// prop value, because `createApp(App, props)` props are static: reactivity has
// to come from the object itself.
export interface Hydration {
  /** True until every summary shard has landed. */
  loading: boolean;
  /** Corpus total, known up front so counts are truthful during loading. */
  total: number | null;
  /** Start (or hurry along) the shard load — e.g. when the user searches. */
  requestAll: () => void;
}
