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

/** One dated event, e.g. { type: "published", value: "2009-06-19" }. */
export interface DocDate {
  type?: string | null;
  value: string;
}

// One bibliographic document as rendered in the index. This shape is the
// contract shared with the Ruby side (Relaton::Cli::IndexItemNormalizer):
// whatever the generator emits as JSON / DOM data-attributes must map here.
//
// The first block is the summary contract present in every delivery mode. The
// second block holds the richer, optional detail-page fields — the generator
// emits them only into the embedded `window.RELATON_INDEX_DATA` payload (and
// only when non-empty), so a `dom`/`static-json` build simply omits them and
// the detail page falls back to the summary fields.
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
}

export interface IndexData {
  title: string;
  documents: IndexDocument[];
  /** ISO timestamp the site was generated (optional, for the footer). */
  generated?: string | null;
}

/** Compact record shape used by search.json (drop-in with the legacy theme). */
export interface CompactRecord {
  r: string; // reference / id
  c: string; // content / title
  t?: string | null; // doctype
  s?: string | null; // stage
  d?: string | null; // date
  u?: string | null; // url (yaml)
  l?: string | null; // link
}

declare global {
  interface Window {
    RELATON_INDEX_DATA?: IndexData;
  }
}
