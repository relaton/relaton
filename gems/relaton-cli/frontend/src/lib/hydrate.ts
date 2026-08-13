import type { IndexData, ShardInfo } from "./types";

// Read the page's index metadata off the mount node. There is exactly one
// delivery mode: the shell carries branding plus the shard layout, and the
// documents themselves arrive from the `search-NNNN.json` shards (see
// ./shards.ts). Nothing is fetched here, so this is synchronous and the app can
// paint immediately instead of waiting on a manifest round-trip.
export interface HydratedIndex {
  /** Branding + an empty document list for the app to fill as shards land. */
  data: IndexData;
  shards: ShardInfo;
}

export function resolveIndex(el: HTMLElement): HydratedIndex {
  return {
    data: {
      title: pageTitle(el),
      description: pageDescription(el),
      documents: [],
      generated: el.dataset.generated || null,
    },
    shards: readShardInfo(el),
  };
}

// A missing or unparseable attribute reads as 0 — an index with no shards,
// which renders as an empty (but correctly branded) page rather than throwing.
function count(value: string | undefined): number {
  const n = Number.parseInt(value ?? "", 10);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

export function readShardInfo(el: HTMLElement): ShardInfo {
  return {
    total: count(el.dataset.total),
    shards: count(el.dataset.shards),
    shardSize: count(el.dataset.shardSize),
    detailShards: count(el.dataset.detailShards),
    detailShardSize: count(el.dataset.detailShardSize),
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

/** The site blurb, carried on the mount node (also the meta description). */
function pageDescription(el: HTMLElement): string | null {
  return el.dataset.description || null;
}
