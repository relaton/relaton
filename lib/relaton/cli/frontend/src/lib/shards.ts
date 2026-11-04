import type {
  CompactRecord,
  DetailRecord,
  IndexDocument,
  ShardInfo,
} from "./types";

// Fetching the numbered JSON shards the generator writes beside index.html.
//
// Summary shards are loaded progressively so the page is usable long before the
// whole corpus has arrived; detail shards are fetched one at a time, only when a
// document panel opens.

/** `search-0007.json` — zero-padded to four digits, matching the generator. */
export function shardPath(prefix: string, index: number): string {
  return `${prefix}-${String(index).padStart(4, "0")}.json`;
}

// A shard that 404s or contains garbage resolves to null rather than throwing,
// so one bad file can't take down the whole load. Three things are checked:
// `res.ok`, because a 404 on GitHub Pages returns an HTML error page that would
// otherwise blow up in res.json(); the parse itself; and that the result is
// actually an array, because a 200 whose body is `{}` or `5` would otherwise
// throw at the call site (in a worker, rejecting the whole load).
async function fetchArray<T>(path: string): Promise<T[] | null> {
  try {
    const res = await fetch(path);
    if (!res.ok) return null;
    const body = await res.json();
    return Array.isArray(body) ? (body as T[]) : null;
  } catch {
    return null;
  }
}

// One retry, because the common failure here is a transient CDN blip mid-deploy
// and the cost of giving up is a permanent hole in the corpus.
async function fetchArrayWithRetry<T>(path: string): Promise<T[] | null> {
  const first = await fetchArray<T>(path);
  if (first) return first;
  return fetchArray<T>(path);
}

export function fromCompact(r: CompactRecord, pos?: number): IndexDocument {
  return {
    id: r.r ?? "",
    title: r.c ?? "",
    doctype: r.t || null,
    stage: r.s || null,
    date: r.d || null,
    link: r.l || null,
    yaml: r.u || null,
    ...(pos === undefined ? {} : { pos }),
  };
}

export interface LoadOptions {
  /** Shards fetched at once. */
  concurrency?: number;
  /** Minimum gap between onBatch calls, in ms. */
  flushMs?: number;
  /** Injectable clock, for tests. */
  now?: () => number;
}

// Load every summary shard, calling `onBatch` with the documents so far.
//
// Two properties matter to the caller:
//
//   * Order. Records are appended in shard order regardless of the order
//     responses arrive in, because the corpus order is what the detail shards'
//     positional lookup is keyed to. A shard that resolves early waits for its
//     predecessors before being appended.
//   * Throttling. App.vue re-filters and re-sorts the entire array on every
//     change, so emitting once per shard would re-sort a growing 166k-element
//     array dozens of times. Batches are coalesced into one emit per window.
export async function loadSearchShards(
  info: ShardInfo,
  onBatch: (docs: IndexDocument[]) => void,
  opts: LoadOptions = {},
): Promise<void> {
  const total = info.shards;
  if (total <= 0) return;

  const flushMs = opts.flushMs ?? 750;
  const now = opts.now ?? (() => Date.now());
  const slots: (IndexDocument[] | null)[] = new Array(total).fill(null);

  let out: IndexDocument[] = [];
  let appendedUpTo = 0; // index of the first slot not yet appended to `out`
  let next = 0;
  // -Infinity, not 0: the first batch must paint immediately whatever epoch the
  // clock uses. With 0 it would only do so because Date.now() happens to be huge.
  let lastEmit = -Infinity;

  const drain = (force: boolean) => {
    let grew = false;
    while (appendedUpTo < total && slots[appendedUpTo]) {
      out = out.concat(slots[appendedUpTo]!);
      slots[appendedUpTo] = null; // release the intermediate array
      appendedUpTo++;
      grew = true;
    }
    if (!grew && !force) return;

    const at = now();
    if (!force && at - lastEmit < flushMs) return;
    lastEmit = at;
    onBatch(out); // new array identity each time, so the caller can reassign
  };

  const worker = async (): Promise<void> => {
    for (let i = next++; i < total; i = next++) {
      const rows = await fetchArrayWithRetry<CompactRecord>(
        shardPath("search", i),
      );
      if (!rows) {
        // The documents are lost, but their absence must not shift anyone
        // else's corpus position — hence the explicit `pos` below.
        console.warn(`relaton-index: shard ${shardPath("search", i)} failed to load`);
        slots[i] = [];
        drain(false);
        continue;
      }
      // Corpus position is assigned here, from the shard number, so it survives
      // a hole left by a failed shard and any later reordering of the array.
      const base = i * info.shardSize;
      slots[i] = rows.map((row, j) => fromCompact(row, base + j));
      drain(false);
    }
  };

  const workers = Math.max(1, Math.min(opts.concurrency ?? 4, total));
  await Promise.all(Array.from({ length: workers }, worker));
  drain(true);
}

export type DetailLoader = (
  index: number,
  id: string,
) => Promise<DetailRecord | null>;

// Fetch-on-demand loader for the detail shards, with a per-shard cache so
// paging through neighbouring documents costs one request, not one per
// document. Concurrent opens within the same shard share a single in-flight
// request.
//
// `index` is the document's position in the full corpus, which is also its
// position across the detail shards. The entry's `r` is checked against the
// document id before its fields are used: if the two families ever fell out of
// step, showing another document's abstract would be worse than showing none,
// so a mismatch falls back to scanning the shard for the right id.
export function createDetailLoader(info: ShardInfo): DetailLoader {
  type Slots = (DetailRecord | null)[];
  const cache = new Map<number, Slots>();
  const inFlight = new Map<number, Promise<Slots>>();

  return async function loadDetail(index, id) {
    const { detailShards, detailShardSize } = info;
    if (detailShards <= 0 || detailShardSize <= 0 || index < 0) return null;

    const shard = Math.floor(index / detailShardSize);
    if (shard >= detailShards) return null;

    let entries = cache.get(shard);
    if (!entries) {
      let pending = inFlight.get(shard);
      if (!pending) {
        pending = fetchArray<DetailRecord | null>(
          shardPath("detail", shard),
        ).then((rows) => rows ?? []);
        inFlight.set(shard, pending);
      }
      entries = await pending;
      cache.set(shard, entries);
      inFlight.delete(shard);
    }

    const slot = entries[index % detailShardSize];
    if (slot && slot.r === id) return slot;
    return entries.find((entry) => entry != null && entry.r === id) ?? null;
  };
}
