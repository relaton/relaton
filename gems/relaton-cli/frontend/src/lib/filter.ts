import type { IndexDocument } from "./types";

export type SortKey = "id" | "date" | "title";
export type SortDir = "asc" | "desc";

/** Lowercased haystack for a document (id + title + doctype). */
export function searchText(doc: IndexDocument): string {
  return `${doc.id} ${doc.title} ${doc.doctype ?? ""}`.toLowerCase();
}

/** Case-insensitive AND-of-terms match over the search haystack. */
export function matchesQuery(doc: IndexDocument, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  const hay = searchText(doc);
  return q.split(/\s+/).every((term) => hay.includes(term));
}

/** Distinct, sorted non-empty values of a field across documents. */
export function distinctValues(
  docs: IndexDocument[],
  key: "doctype" | "stage",
): string[] {
  const set = new Set<string>();
  for (const d of docs) {
    const v = d[key];
    if (v) set.add(v);
  }
  return Array.from(set).sort((a, b) => a.localeCompare(b));
}

// Natural (human) comparison so "CCRI 2" sorts before "CCRI 10".
const collator = new Intl.Collator(undefined, {
  numeric: true,
  sensitivity: "base",
});

export function compareDocuments(
  a: IndexDocument,
  b: IndexDocument,
  key: SortKey,
  dir: SortDir,
): number {
  let cmp = 0;
  switch (key) {
    case "date":
      // Missing dates sort last regardless of direction feel — use empty string.
      cmp = (a.date ?? "").localeCompare(b.date ?? "");
      break;
    case "title":
      cmp = collator.compare(a.title, b.title);
      break;
    case "id":
    default:
      cmp = collator.compare(a.id, b.id);
      break;
  }
  return dir === "asc" ? cmp : -cmp;
}

export interface FilterOptions {
  query: string;
  doctypes: Set<string>;
  stages: Set<string>;
  sortKey: SortKey;
  sortDir: SortDir;
}

/** Apply search + facet filters, then sort. Pure — safe to unit test. */
export function applyFilters(
  docs: IndexDocument[],
  opts: FilterOptions,
): IndexDocument[] {
  const filtered = docs.filter((d) => {
    if (!matchesQuery(d, opts.query)) return false;
    if (opts.doctypes.size && !(d.doctype && opts.doctypes.has(d.doctype))) {
      return false;
    }
    if (opts.stages.size && !(d.stage && opts.stages.has(d.stage))) {
      return false;
    }
    return true;
  });
  return filtered.sort((a, b) =>
    compareDocuments(a, b, opts.sortKey, opts.sortDir),
  );
}
