// @vitest-environment happy-dom
import { afterEach, describe, expect, it } from "vitest";
import { readShardInfo, resolveIndex } from "./hydrate";

function mount(attrs: Record<string, string> = {}): HTMLElement {
  const el = document.createElement("div");
  el.id = "relaton-index-app";
  Object.entries(attrs).forEach(([k, v]) => el.setAttribute(`data-${k}`, v));
  document.body.appendChild(el);
  return el;
}

afterEach(() => {
  document.body.innerHTML = "";
  document.title = "";
});

describe("resolveIndex", () => {
  it("reads the branding off the mount node", () => {
    const el = mount({
      title: "BIPM Index",
      description: "The BIPM standards index.",
      generated: "2026-01-01",
    });
    const { data } = resolveIndex(el);
    expect(data.title).toBe("BIPM Index");
    expect(data.description).toBe("The BIPM standards index.");
    expect(data.generated).toBe("2026-01-01");
  });

  // Documents arrive from the shards; the shell carries none, so the app paints
  // immediately with an empty list rather than awaiting anything.
  it("starts with no documents", () => {
    const { data } = resolveIndex(mount({ total: "42", shards: "3" }));
    expect(data.documents).toEqual([]);
  });

  it("exposes the shard layout alongside the branding", () => {
    const { shards } = resolveIndex(mount({ total: "42", shards: "3" }));
    expect(shards.total).toBe(42);
    expect(shards.shards).toBe(3);
  });

  it("falls back to the page h1, then document.title, then a default", () => {
    document.title = "From document title";
    expect(resolveIndex(mount()).data.title).toBe("From document title");

    document.body.innerHTML = "";
    const h1 = document.createElement("h1");
    h1.textContent = "From heading";
    document.body.appendChild(h1);
    expect(resolveIndex(mount()).data.title).toBe("From heading");

    document.body.innerHTML = "";
    document.title = "";
    expect(resolveIndex(mount()).data.title).toBe("Relaton Index");
  });

  it("reports no description when the attribute is absent or blank", () => {
    expect(resolveIndex(mount()).data.description).toBeNull();
    expect(resolveIndex(mount({ description: "" })).data.description).toBeNull();
  });
});

describe("readShardInfo", () => {
  it("reads the five scalars the generator writes", () => {
    const el = mount({
      total: "166658",
      shards: "34",
      "shard-size": "5000",
      "detail-shards": "334",
      "detail-shard-size": "500",
    });
    expect(readShardInfo(el)).toEqual({
      total: 166658,
      shards: 34,
      shardSize: 5000,
      detailShards: 334,
      detailShardSize: 500,
    });
  });

  // An index with zero shards renders as an empty but correctly branded page —
  // better than throwing on a malformed shell.
  it("treats missing, blank or non-numeric attributes as zero", () => {
    expect(readShardInfo(mount())).toEqual({
      total: 0,
      shards: 0,
      shardSize: 0,
      detailShards: 0,
      detailShardSize: 0,
    });
    expect(readShardInfo(mount({ shards: "" })).shards).toBe(0);
    expect(readShardInfo(mount({ shards: "lots" })).shards).toBe(0);
    expect(readShardInfo(mount({ shards: "-3" })).shards).toBe(0);
  });

  it("reports zero detail shards for a --no-detail build", () => {
    const el = mount({ total: "2", shards: "1", "detail-shards": "0" });
    expect(readShardInfo(el).detailShards).toBe(0);
  });
});
