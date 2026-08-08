// Reflects the current pagination page in the URL as `?page=N`, so a reload or a
// shared/bookmarked link lands on the same page. This is the app's only
// URL-synced state (search/facets/sort stay in-memory; view/theme use
// localStorage). Page 1 omits the param to keep the canonical URL clean.

const PARAM = "page";

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
