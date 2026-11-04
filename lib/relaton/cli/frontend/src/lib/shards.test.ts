// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  createDetailLoader,
  loadSearchShards,
  shardPath,
} from "./shards";
import type { CompactRecord, DetailRecord, ShardInfo } from "./types";
import { deferred, stubFetch } from "../test/fetch";

afterEach(() => {
  vi.unstubAllGlobals();
});

function info(over: Partial<ShardInfo> = {}): ShardInfo {
  return {
    total: 0,
    shards: 0,
    shardSize: 3,
    detailShards: 0,
    detailShardSize: 2,
    ...over,
  };
}

function rows(...ids: string[]): CompactRecord[] {
  return ids.map((id) => ({ r: id, c: `Title ${id}` }));
}

describe("shardPath", () => {
  it("zero-pads to four digits, matching the generator", () => {
    expect(shardPath("search", 0)).toBe("search-0000.json");
    expect(shardPath("search", 7)).toBe("search-0007.json");
    expect(shardPath("detail", 1234)).toBe("detail-1234.json");
  });
});

describe("loadSearchShards", () => {
  it("does nothing when there are no shards", async () => {
    const onBatch = vi.fn();
    await loadSearchShards(info({ shards: 0 }), onBatch);
    expect(onBatch).not.toHaveBeenCalled();
  });

  it("maps compact records onto documents", async () => {
    stubFetch({
      "search-0000.json": [
        { r: "A", c: "Title A", t: "standard", s: "published", d: "2020-01-01", u: "a.yaml", l: "https://x/a" },
      ],
    });
    const batches: string[][] = [];
    await loadSearchShards(info({ shards: 1 }), (docs) =>
      batches.push(docs.map((d) => d.id)),
    );
    expect(batches[batches.length - 1]).toEqual(["A"]);
  });

  // The detail shards are addressed by corpus position, so a shard that arrives
  // early must not jump the queue.
  it("appends in shard order even when responses resolve out of order", async () => {
    const first = deferred<CompactRecord[]>();
    stubFetch({
      "search-0000.json": () => first.promise,
      "search-0001.json": rows("B1", "B2"),
      "search-0002.json": rows("C1"),
    });

    const seen: string[][] = [];
    const done = loadSearchShards(
      info({ shards: 3 }),
      (docs) => seen.push(docs.map((d) => d.id)),
      { flushMs: 0 },
    );

    // Let shards 1 and 2 settle while 0 is still outstanding.
    await Promise.resolve();
    await Promise.resolve();
    first.resolve(rows("A1", "A2"));
    await done;

    expect(seen[seen.length - 1]).toEqual(["A1", "A2", "B1", "B2", "C1"]);
    // Nothing was emitted before shard 0 landed.
    expect(seen.every((batch) => batch.length === 0 || batch[0] === "A1")).toBe(true);
  });

  it("coalesces emissions instead of firing once per shard", async () => {
    stubFetch({
      "search-0000.json": rows("A"),
      "search-0001.json": rows("B"),
      "search-0002.json": rows("C"),
      "search-0003.json": rows("D"),
    });

    const onBatch = vi.fn();
    // A clock that never advances: the first batch still paints immediately, the
    // two in the middle are suppressed, and the final forced emit carries them.
    await loadSearchShards(info({ shards: 4 }), onBatch, {
      flushMs: 10_000,
      now: () => 1_000,
      concurrency: 1,
    });

    expect(onBatch).toHaveBeenCalledTimes(2);
    const ids = (call: number) =>
      onBatch.mock.calls[call][0].map((d: { id: string }) => d.id);
    expect(ids(0)).toEqual(["A"]);
    expect(ids(1)).toEqual(["A", "B", "C", "D"]);
  });

  it("paints the first batch immediately regardless of the clock's epoch", async () => {
    stubFetch({
      "search-0000.json": rows("A"),
      "search-0001.json": rows("B"),
    });

    const onBatch = vi.fn();
    // A monotonic-style clock starting near zero would, with a naive lastEmit of
    // 0, suppress the very first paint.
    await loadSearchShards(info({ shards: 2 }), onBatch, {
      flushMs: 750,
      now: () => 5,
      concurrency: 1,
    });

    expect(onBatch.mock.calls[0][0].map((d: { id: string }) => d.id)).toEqual(["A"]);
  });

  it("stamps each document with its corpus position", async () => {
    stubFetch({
      "search-0000.json": rows("A1", "A2", "A3"),
      "search-0001.json": rows("B1", "B2"),
    });

    let docs: { id: string; pos?: number }[] = [];
    await loadSearchShards(info({ shards: 2, shardSize: 3 }), (d) => {
      docs = d;
    });
    // Shard 1 starts at 1 * shardSize, not at "however many arrived so far".
    expect(docs.map((d) => d.pos)).toEqual([0, 1, 2, 3, 4]);
  });

  it("skips a failing shard without losing the rest", async () => {
    stubFetch({
      "search-0000.json": rows("A"),
      "search-0001.json": 404,
      "search-0002.json": rows("C"),
    });

    const batches: string[][] = [];
    await loadSearchShards(
      info({ shards: 3 }),
      (docs) => batches.push(docs.map((d) => d.id)),
      { flushMs: 0 },
    );
    expect(batches[batches.length - 1]).toEqual(["A", "C"]);
  });

  // The documents in a lost shard are gone, but their absence must not shift
  // everyone else: positions are what address the detail shards, so a hole that
  // renumbered the survivors would silently point every later document at the
  // wrong detail shard — and the id check there can only scan the shard it was
  // sent to, so it could never recover.
  it("keeps corpus positions correct across a hole left by a failed shard", async () => {
    stubFetch({
      "search-0000.json": rows("A1", "A2"),
      "search-0001.json": 404,
      "search-0002.json": rows("C1", "C2"),
    });

    let docs: { id: string; pos?: number }[] = [];
    await loadSearchShards(info({ shards: 3, shardSize: 2 }), (d) => {
      docs = d;
    });

    expect(docs.map((d) => d.id)).toEqual(["A1", "A2", "C1", "C2"]);
    // C1 is at array index 2 but corpus position 4.
    expect(docs.map((d) => d.pos)).toEqual([0, 1, 4, 5]);
  });

  it("retries a shard once before giving up", async () => {
    let attempts = 0;
    stubFetch({
      "search-0000.json": () => {
        attempts++;
        return attempts === 1 ? 503 : rows("A1", "A2");
      },
    });

    let docs: { id: string }[] = [];
    await loadSearchShards(info({ shards: 1, shardSize: 2 }), (d) => {
      docs = d;
    });

    expect(attempts).toBe(2);
    expect(docs.map((d) => d.id)).toEqual(["A1", "A2"]);
  });

  // A 200 whose body is an object rather than an array used to throw inside the
  // worker, rejecting the whole load and skipping the final forced emit — so
  // every throttled batch since the last emit was lost, plus an unhandled
  // rejection.
  it("survives a shard whose body is valid JSON but not an array", async () => {
    stubFetch({
      "search-0000.json": rows("A"),
      "search-0001.json": { not: "an array" },
      "search-0002.json": rows("C"),
    });

    const batches: string[][] = [];
    await expect(
      loadSearchShards(
        info({ shards: 3 }),
        (docs) => batches.push(docs.map((d) => d.id)),
        { flushMs: 10_000, now: () => 1_000 },
      ),
    ).resolves.toBeUndefined();

    expect(batches[batches.length - 1]).toEqual(["A", "C"]);
  });

  // A 404 on GitHub Pages returns an HTML error page; without the res.ok check
  // that would throw inside res.json() and look like a network failure.
  it("treats a non-OK response as an empty shard", async () => {
    stubFetch({ "search-0000.json": 500 });
    const batches: string[][] = [];
    await loadSearchShards(info({ shards: 1 }), (docs) =>
      batches.push(docs.map((d) => d.id)),
    );
    expect(batches[batches.length - 1]).toEqual([]);
  });

  it("requests each shard exactly once", async () => {
    const stub = stubFetch({
      "search-0000.json": rows("A"),
      "search-0001.json": rows("B"),
    });
    await loadSearchShards(info({ shards: 2 }), () => {});
    expect(stub.calls.sort()).toEqual(["search-0000.json", "search-0001.json"]);
  });
});

describe("createDetailLoader", () => {
  const detail = (id: string): DetailRecord => ({
    r: id,
    abstract: `About ${id}`,
  });

  const shardedInfo = info({ detailShards: 3, detailShardSize: 2 });

  it("resolves a document by its corpus position", async () => {
    stubFetch({ "detail-0001.json": [detail("C"), detail("D")] });
    const load = createDetailLoader(shardedInfo);
    // index 3 -> shard 1, slot 1
    await expect(load(3, "D")).resolves.toEqual(detail("D"));
  });

  it("returns null when detail shards were not built", async () => {
    const load = createDetailLoader(info({ detailShards: 0 }));
    await expect(load(0, "A")).resolves.toBeNull();
  });

  it("returns null for a position beyond the last shard", async () => {
    const load = createDetailLoader(shardedInfo);
    await expect(load(999, "Z")).resolves.toBeNull();
  });

  it("returns null for a null slot (a document with no detail fields)", async () => {
    stubFetch({ "detail-0000.json": [null, null] });
    const load = createDetailLoader(shardedInfo);
    await expect(load(0, "A")).resolves.toBeNull();
  });

  // Position is derived, not stored, so it has to be checked. Showing another
  // document's abstract would be worse than showing none.
  it("falls back to an id scan when the slot holds a different document", async () => {
    stubFetch({ "detail-0000.json": [detail("WRONG"), detail("A")] });
    const load = createDetailLoader(shardedInfo);
    await expect(load(0, "A")).resolves.toEqual(detail("A"));
  });

  it("returns null when the id is nowhere in the shard", async () => {
    stubFetch({ "detail-0000.json": [detail("X"), detail("Y")] });
    const load = createDetailLoader(shardedInfo);
    await expect(load(0, "A")).resolves.toBeNull();
  });

  it("fetches a shard once and serves later hits from cache", async () => {
    const stub = stubFetch({ "detail-0000.json": [detail("A"), detail("B")] });
    const load = createDetailLoader(shardedInfo);

    await load(0, "A");
    await load(1, "B");

    expect(stub.calls).toEqual(["detail-0000.json"]);
  });

  it("shares one request between concurrent opens in the same shard", async () => {
    const stub = stubFetch({ "detail-0000.json": [detail("A"), detail("B")] });
    const load = createDetailLoader(shardedInfo);

    const [a, b] = await Promise.all([load(0, "A"), load(1, "B")]);

    expect(stub.calls).toEqual(["detail-0000.json"]);
    expect(a).toEqual(detail("A"));
    expect(b).toEqual(detail("B"));
  });

  it("returns null when the shard request fails", async () => {
    stubFetch({ "detail-0000.json": 404 });
    const load = createDetailLoader(shardedInfo);
    await expect(load(0, "A")).resolves.toBeNull();
  });

  it("returns null when the shard body is not an array", async () => {
    stubFetch({ "detail-0000.json": { oops: true } });
    const load = createDetailLoader(shardedInfo);
    await expect(load(0, "A")).resolves.toBeNull();
  });
});
