// One bibliographic document as rendered in the index. This shape is the
// contract shared with the Ruby side (Relaton::Cli::IndexItemNormalizer):
// whatever the generator emits as JSON / DOM data-attributes must map here.
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
