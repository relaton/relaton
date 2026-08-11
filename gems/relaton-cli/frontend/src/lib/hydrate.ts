import type { CompactRecord, IndexData, IndexDocument } from "./types";

// Resolve the index data for the mounted app in priority order, matching the
// three delivery modes the generator can emit:
//   1. `window.RELATON_INDEX_DATA`  — embedded JSON in a <script> tag
//   2. pre-rendered `.document` DOM  — crawler-indexable data-* attributes
//   3. `fetch(data-src)`             — a static search.json sidecar
//
// (1) and (2) return synchronously; (3) is async. Callers get a Promise so all
// three are handled uniformly.
export function resolveIndexData(el: HTMLElement): Promise<IndexData> {
  if (window.RELATON_INDEX_DATA) {
    return Promise.resolve(normalize(window.RELATON_INDEX_DATA, el));
  }

  const fromDom = readFromDom(el);
  if (fromDom) return Promise.resolve(fromDom);

  const src = el.dataset.src;
  if (src) return fetchSearchJson(src, el);

  return Promise.resolve({
    title: pageTitle(el),
    description: pageDescription(el),
    documents: [],
  });
}

function normalize(data: IndexData, el: HTMLElement): IndexData {
  return {
    title: data.title || "Relaton Index",
    description: data.description ?? pageDescription(el),
    documents: Array.isArray(data.documents) ? data.documents : [],
    generated: data.generated ?? null,
  };
}

function pageTitle(el: HTMLElement): string {
  return (
    el.dataset.title ||
    document.querySelector("h1")?.textContent?.trim() ||
    document.title ||
    "Relaton Index"
  );
}

// The site blurb, carried on the mount node in every mode (the embedded JSON
// also has it, and wins there — see normalize()).
function pageDescription(el: HTMLElement): string | null {
  return el.dataset.description || null;
}

// Parse the server-rendered crawler DOM: each `.document` node carries the
// document fields as data-* attributes.
function readFromDom(el: HTMLElement): IndexData | null {
  const nodes = el.querySelectorAll<HTMLElement>(".documents .document");
  if (!nodes.length) return null;

  const documents: IndexDocument[] = Array.from(nodes).map((n) => ({
    id: n.dataset.id ?? "",
    title: n.dataset.title ?? "",
    doctype: n.dataset.doctype || null,
    stage: n.dataset.stage || null,
    date: n.dataset.date || null,
    link: n.dataset.link || null,
    yaml: n.dataset.href || null,
  }));

  return {
    title: pageTitle(el),
    description: pageDescription(el),
    documents,
    generated: el.dataset.generated || null,
  };
}

async function fetchSearchJson(src: string, el: HTMLElement): Promise<IndexData> {
  try {
    const res = await fetch(src);
    const rows = (await res.json()) as CompactRecord[];
    const documents: IndexDocument[] = rows.map((r) => ({
      id: r.r ?? "",
      title: r.c ?? "",
      doctype: r.t || null,
      stage: r.s || null,
      date: r.d || null,
      link: r.l || null,
      yaml: r.u || null,
    }));
    return { title: pageTitle(el), description: pageDescription(el), documents };
  } catch {
    return { title: pageTitle(el), description: pageDescription(el), documents: [] };
  }
}
