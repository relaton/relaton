// Reflects two pieces of view state in the URL so a reload / shared / bookmarked
// link restores it: the pagination page (`?page=N`) and the open detail document
// (`?doc=<id>`). Both go through the History API, preserve any other params, and
// are synced back on Back/Forward via a `popstate` listener in App.vue.
// (search/facets/sort stay in-memory; view/theme use localStorage.) Page 1 and a
// closed detail omit their param to keep the canonical URL clean.

const PARAM = "page";
const DOC_PARAM = "doc";

/**
 * Parse the `page` query param. Returns an integer >= 1, or 1 for anything
 * invalid (missing, zero, negative, fractional, non-numeric).
 */
export function readPageFromUrl(
  search: string = typeof window !== "undefined" ? window.location.search : "",
): number {
  const raw = new URLSearchParams(search).get(PARAM);
  if (raw === null) return 1;
  const n = Number(raw);
  return Number.isInteger(n) && n >= 1 ? n : 1;
}

/**
 * Reflect `page` into the URL, preserving any other query params. Page 1 drops
 * the param. `mode: "push"` adds a history entry (user navigation, so
 * Back/Forward walk pages); `"replace"` (default) updates in place (restore,
 * clamp, filter-reset).
 */
export function writePageToUrl(
  page: number,
  mode: "push" | "replace" = "replace",
): void {
  if (typeof window === "undefined" || !window.history) return;
  const url = new URL(window.location.href);
  if (page <= 1) url.searchParams.delete(PARAM);
  else url.searchParams.set(PARAM, String(page));
  // Relative target avoids origin surprises across dev/gem/host contexts.
  const target = `${url.pathname}${url.search}${url.hash}`;
  if (mode === "push") window.history.pushState(window.history.state, "", target);
  else window.history.replaceState(window.history.state, "", target);
}

/**
 * A relative, shareable link to a document's detail page. Used for the real
 * anchors that SPA-navigation intercepts — the list rows and the intra-dataset
 * relation links — so middle-click / open-in-new-tab still work. Built with the
 * same `URLSearchParams` encoding as `writeDocToUrl`, so the two agree exactly.
 */
export function docHref(id: string): string {
  return `?${new URLSearchParams({ [DOC_PARAM]: id }).toString()}`;
}

/**
 * Parse the `doc` query param (the open detail document's id). Returns the
 * decoded id, or null when absent/blank. `URLSearchParams` handles decoding, so
 * ids with spaces/parens round-trip with `writeDocToUrl`.
 */
export function readDocFromUrl(
  search: string = typeof window !== "undefined" ? window.location.search : "",
): string | null {
  const raw = new URLSearchParams(search).get(DOC_PARAM);
  return raw && raw.trim() !== "" ? raw : null;
}

/**
 * Reflect the open detail document into the URL, preserving other params (e.g.
 * `page`, so closing the detail returns to the same list page). A null id drops
 * the param. `mode: "push"` adds a history entry (opening/closing a detail, so
 * Back/Forward walk in and out of it); `"replace"` (default) updates in place.
 */
export function writeDocToUrl(
  id: string | null,
  mode: "push" | "replace" = "replace",
): void {
  if (typeof window === "undefined" || !window.history) return;
  const url = new URL(window.location.href);
  if (!id) url.searchParams.delete(DOC_PARAM);
  else url.searchParams.set(DOC_PARAM, id);
  const target = `${url.pathname}${url.search}${url.hash}`;
  if (mode === "push") window.history.pushState(window.history.state, "", target);
  else window.history.replaceState(window.history.state, "", target);
}
