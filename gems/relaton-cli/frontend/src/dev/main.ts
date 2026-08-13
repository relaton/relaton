// Dev-only entry: shard the sample dataset in memory, serve it over a stubbed
// fetch, and boot the app exactly as a generated page would.
// Excluded from the production library build (which uses src/app.ts).
//
// This mirrors what Relaton::Cli::IndexSiteGenerator writes — the mount-node
// scalars plus `search-NNNN.json` / `detail-NNNN.json` — so `npm run dev`
// exercises the real hydration path instead of a shortcut that only exists here.
// The shard sizes are deliberately tiny so progressive loading is visible.
import sample from "./sample-data.json";
import type {
  CompactRecord,
  DetailRecord,
  IndexData,
  IndexDocument,
} from "../lib/types";

const SHARD_SIZE = 3;
const DETAIL_SHARD_SIZE = 2;

const data = sample as IndexData;
const documents = data.documents ?? [];

const SUMMARY_KEYS: readonly string[] = [
  "id",
  "title",
  "doctype",
  "stage",
  "date",
  "link",
  "yaml",
];

function toCompact(doc: IndexDocument): CompactRecord {
  return {
    r: doc.id,
    c: doc.title,
    t: doc.doctype,
    s: doc.stage,
    d: doc.date,
    u: doc.yaml,
    l: doc.link,
  };
}

function toDetail(doc: IndexDocument): DetailRecord | null {
  const rest = Object.fromEntries(
    Object.entries(doc).filter(([key]) => !SUMMARY_KEYS.includes(key)),
  );
  if (Object.keys(rest).length === 0) return null;
  return { r: doc.id, ...rest } as DetailRecord;
}

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

const summaryShards = chunk(documents.map(toCompact), SHARD_SIZE);
const detailShards = chunk(documents.map(toDetail), DETAIL_SHARD_SIZE);

const files = new Map<string, unknown>();
summaryShards.forEach((rows, i) => {
  files.set(`search-${String(i).padStart(4, "0")}.json`, rows);
});
detailShards.forEach((rows, i) => {
  files.set(`detail-${String(i).padStart(4, "0")}.json`, rows);
});

const realFetch = window.fetch.bind(window);
window.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
  const url = typeof input === "string" ? input : String((input as Request).url ?? input);
  const name = url.split("/").pop() ?? "";
  const body = files.get(name);
  if (body !== undefined) {
    return Promise.resolve(
      new Response(JSON.stringify(body), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  }
  return realFetch(input as RequestInfo, init);
}) as typeof window.fetch;

const el = document.getElementById("relaton-index-app");
if (el) {
  el.dataset.title = data.title ?? "Relaton Index";
  if (data.description) el.dataset.description = data.description;
  if (data.generated) el.dataset.generated = data.generated;
  el.dataset.total = String(documents.length);
  el.dataset.shards = String(summaryShards.length);
  el.dataset.shardSize = String(SHARD_SIZE);
  el.dataset.detailShards = String(detailShards.length);
  el.dataset.detailShardSize = String(DETAIL_SHARD_SIZE);
}

import("../app");
