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
  return `${docPathBase()}/doc/${encodeURIComponent(id)}`;
}

// The app root (site base path) for path-based doc URLs: whatever precedes a
// trailing `/doc/<id>` segment on the current pathname, or the full pathname
// when none (the list view at `/` or `/index.html`).
function docPathBase(): string {
  const p = window.location.pathname;
  const cut = p.lastIndexOf("/doc/");
  const base = cut >= 0 ? p.slice(0, cut) : p.replace(/\/index\.html$/, "");
  return base === "/" ? "" : base.replace(/\/+$/, "");
}

/**
 * Parse the `doc` query param (the open detail document's id). Returns the
 * decoded id, or null when absent/blank. `URLSearchParams` handles decoding, so
 * ids with spaces/parens round-trip with `writeDocToUrl`.
 */
export function readDocFromUrl(
  search: string = typeof window !== "undefined" ? window.location.search : "",
): string | null {
  if (search === (typeof window !== "undefined" ? window.location.search : "")) {
    // Path-based URLs first: `/doc/<id>` served via the 404 fallback (GitHub
    // Pages has no rewrites) or written by writeDocToUrl below.
    const m = window.location.pathname.match(/\/doc\/([^/?#]+)$/);
    if (m) {
      const fromPath = decodeURIComponent(m[1]);
      if (fromPath.trim() !== "") return fromPath;
    }
  }
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
  if (id) {
    // Canonical per-document URLs are path-based (`<root>/doc/<id>`) so each
    // document has a shareable address; `?doc=` remains readable for links
    // written before paths existed and by the 404 fallback redirect.
    const base = docPathBase();
    const target = `${base}/doc/${encodeURIComponent(id)}${url.search && url.searchParams.has(PARAM) ? `?${url.searchParams}` : ""}${url.hash}`;
    if (mode === "push") window.history.pushState(window.history.state, "", target);
    else window.history.replaceState(window.history.state, "", target);
    return;
  }
  url.searchParams.delete(DOC_PARAM);
  const target = `${docPathBase()}/${url.search}${url.hash}`;
  if (mode === "push") window.history.pushState(window.history.state, "", target);
  else window.history.replaceState(window.history.state, "", target);
}
