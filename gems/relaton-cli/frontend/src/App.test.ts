// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { reactive } from "vue";
import { flushPromises, mount } from "@vue/test-utils";
import App from "./App.vue";
import type { DetailRecord, Hydration, IndexData } from "./lib/types";

function hydration(over: Partial<Hydration> = {}): Hydration {
  return { loading: false, total: null, requestAll: () => {}, ...over };
}

const data: IndexData = {
  title: "BIPM Index",
  documents: [
    { id: "CCRI 2", title: "Second meeting", doctype: "meeting-report", stage: "published", date: "2009-06-19", link: null, yaml: "ccri/2.yaml" },
    { id: "CCRI 10", title: "Tenth gathering", doctype: "meeting-report", stage: "draft", date: "2019-01-01", link: null, yaml: "ccri/10.yaml" },
    { id: "SI Brochure", title: "The SI", doctype: "brochure", stage: "published", date: "2019-05-20", link: "http://x", yaml: "si.yaml" },
  ],
};

const many: IndexData = {
  title: "Big Index",
  documents: Array.from({ length: 60 }, (_, i) => ({
    id: `DOC ${i + 1}`, title: `Title ${i + 1}`,
    doctype: "report", stage: "published", date: "2020-01-01",
    link: null, yaml: `d/${i + 1}.yaml`,
  })),
};

beforeEach(() => {
  // A mount node is expected to exist (goto() scrolls it into view).
  document.body.innerHTML = '<div id="relaton-index-app"></div>';
  // Reset the URL so ?page= from one test doesn't leak into the next.
  window.history.replaceState(null, "", "/");
});

describe("App island", () => {
  it("renders a row per document and the title", () => {
    const w = mount(App, { props: { data } });
    expect(w.text()).toContain("BIPM Index");
    expect(w.findAll(".document")).toHaveLength(3);
  });

  it("renders the description as the header subtitle when given", () => {
    const w = mount(App, { props: { data: { ...data, description: "The BIPM index." } } });
    expect(w.text()).toContain("The BIPM index.");
    expect(w.text()).not.toContain("Please use the provided Relaton DocID");
  });

  it("falls back to the default subtitle without a description", () => {
    const w = mount(App, { props: { data } });
    expect(w.text()).toContain("Please use the provided Relaton DocID to refer to an item.");
  });

  it("filters by the search query", async () => {
    const w = mount(App, { props: { data } });
    await w.find('input[type="search"]').setValue("brochure");
    expect(w.findAll(".document")).toHaveLength(1);
    expect(w.text()).toContain("The SI");
  });

  it("shows the count summary", () => {
    const w = mount(App, { props: { data } });
    expect(w.text()).toContain("3 of 3 documents");
  });

  it("paginates to the viewport and mirrors the controls top and bottom", async () => {
    const original = window.innerHeight;
    Object.defineProperty(window, "innerHeight", { value: 400, configurable: true });
    try {
      const w = mount(App, { props: { data: many } });
      await flushPromises();

      const rows = w.findAll(".document").length;
      expect(rows).toBeGreaterThan(0);
      expect(rows).toBeLessThan(60); // paginated, not all 60 at once

      // Pagination is rendered both above and below the list.
      const navs = w.findAll('nav[aria-label="Pagination"]');
      expect(navs).toHaveLength(2);
    } finally {
      Object.defineProperty(window, "innerHeight", { value: original, configurable: true });
    }
  });
});

describe("page number in the URL", () => {
  const withSmallViewport = async (fn: () => Promise<void>) => {
    const original = window.innerHeight;
    Object.defineProperty(window, "innerHeight", { value: 400, configurable: true });
    try {
      await fn();
    } finally {
      Object.defineProperty(window, "innerHeight", { value: original, configurable: true });
    }
  };

  it("restores the current page from ?page= on mount", async () => {
    window.history.replaceState(null, "", "/?page=2");
    await withSmallViewport(async () => {
      const w = mount(App, { props: { data: many } });
      await flushPromises();
      expect(w.text()).toContain("Page 2 of");
    });
  });

  it("pushes a new history entry and updates the URL when paging next", async () => {
    await withSmallViewport(async () => {
      const w = mount(App, { props: { data: many } });
      await flushPromises();
      const push = vi.spyOn(window.history, "pushState");

      // Click the first Prev/Next nav's "Next" button.
      await w.findAll('nav[aria-label="Pagination"] button')
        .find((b) => b.text() === "Next")!.trigger("click");
      await flushPromises();

      expect(push).toHaveBeenCalledTimes(1);
      expect(new URLSearchParams(window.location.search).get("page")).toBe("2");
    });
  });

  it("clamps an out-of-range ?page= to the last page on mount", async () => {
    window.history.replaceState(null, "", "/?page=999");
    await withSmallViewport(async () => {
      const w = mount(App, { props: { data: many } });
      await flushPromises();
      // 60 docs at the small-viewport page size → 6 pages.
      expect(w.text()).toContain("Page 6 of 6");
      expect(new URLSearchParams(window.location.search).get("page")).toBe("6");
    });
  });

  it("syncs the page from the URL on Back/Forward (popstate)", async () => {
    await withSmallViewport(async () => {
      const w = mount(App, { props: { data: many } });
      await flushPromises();
      expect(w.text()).toContain("Page 1 of");

      // Simulate the browser navigating Back to a ?page=3 history entry.
      window.history.replaceState(null, "", "/?page=3");
      window.dispatchEvent(new PopStateEvent("popstate"));
      await flushPromises();
      expect(w.text()).toContain("Page 3 of");
    });
  });

  it("resets to page 1 and clears the param when the filter changes", async () => {
    window.history.replaceState(null, "", "/?page=3");
    await withSmallViewport(async () => {
      const w = mount(App, { props: { data: many } });
      await flushPromises();
      expect(w.text()).toContain("Page 3 of");

      await w.find('input[type="search"]').setValue("Title 1");
      await flushPromises();

      expect(new URLSearchParams(window.location.search).has("page")).toBe(false);
    });
  });
});

describe("document detail page", () => {
  const isDetail = (w: ReturnType<typeof mount>) =>
    w.find('[aria-label="Back to index"]').exists();

  it("opens the detail view and sets a path-based /doc/ URL when a row is clicked", async () => {
    const w = mount(App, { props: { data } });
    // The first row's DocID link.
    await w.find(".document a").trigger("click");
    await flushPromises();

    expect(isDetail(w)).toBe(true);
    expect(w.find('input[type="search"]').exists()).toBe(false);
    expect(decodeURIComponent(window.location.pathname)).toBe("/doc/CCRI 2");
  });

  it("restores the open document from ?doc= on mount", async () => {
    window.history.replaceState(null, "", "/?doc=SI%20Brochure");
    const w = mount(App, { props: { data } });
    await flushPromises();

    expect(isDetail(w)).toBe(true);
    expect(w.text()).toContain("The SI");
  });

  it("returns to the list on Back/Forward (popstate)", async () => {
    const w = mount(App, { props: { data } });
    await w.find(".document a").trigger("click");
    await flushPromises();
    expect(isDetail(w)).toBe(true);

    // Simulate the browser navigating Back to the param-free list URL.
    window.history.replaceState(null, "", "/");
    window.dispatchEvent(new PopStateEvent("popstate"));
    await flushPromises();

    expect(isDetail(w)).toBe(false);
    expect(w.find('input[type="search"]').exists()).toBe(true);
  });

  it("falls back to the list for an unknown ?doc=", async () => {
    window.history.replaceState(null, "", "/?doc=NOPE");
    const w = mount(App, { props: { data } });
    await flushPromises();

    expect(isDetail(w)).toBe(false);
    expect(w.find('input[type="search"]').exists()).toBe(true);
  });

  it("goes back to the list when the detail Back control is clicked", async () => {
    const w = mount(App, { props: { data } });
    await w.find(".document a").trigger("click");
    await flushPromises();
    expect(isDetail(w)).toBe(true);

    await w.find('[aria-label="Back to index"]').trigger("click");
    await flushPromises();

    expect(isDetail(w)).toBe(false);
    expect(new URLSearchParams(window.location.search).has("doc")).toBe(false);
  });
});

// Summary shards arrive progressively, so for a while the app holds a corpus it
// knows is incomplete. Anything that treats "absent" as "does not exist" has to
// wait for `loading` to clear, or every deep link into a large index breaks.
describe("progressive shard loading", () => {
  const isDetail = (w: ReturnType<typeof mount>) =>
    w.find('[aria-label="Back to index"]').exists();

  it("reports the corpus total, not just what has landed", () => {
    const w = mount(App, {
      props: { data, hydration: hydration({ loading: true, total: 166658 }) },
    });
    expect(w.text()).toContain("3 of 166658 documents");
    expect(w.text()).toContain("loading…");
  });

  it("shows no loading hint once every shard has landed", () => {
    const w = mount(App, { props: { data, hydration: hydration({ total: 3 }) } });
    expect(w.text()).not.toContain("loading…");
  });

  it("keeps an unresolved ?doc= while loading instead of bouncing to the list", async () => {
    window.history.replaceState(null, "", "/?doc=NOT%20YET");
    const w = mount(App, {
      props: { data, hydration: hydration({ loading: true, total: 99 }) },
    });
    await flushPromises();

    expect(new URLSearchParams(window.location.search).get("doc")).toBe("NOT YET");
    expect(isDetail(w)).toBe(false);
  });

  it("asks for the rest of the corpus when a deep link is unresolved", async () => {
    window.history.replaceState(null, "", "/?doc=NOT%20YET");
    const requestAll = vi.fn();
    mount(App, {
      props: { data, hydration: hydration({ loading: true, total: 99, requestAll }) },
    });
    await flushPromises();

    expect(requestAll).toHaveBeenCalled();
  });

  it("drops a still-unresolved ?doc= once loading finishes", async () => {
    window.history.replaceState(null, "", "/?doc=NEVER%20ARRIVES");
    const hyd = reactive(hydration({ loading: true, total: 99 }));
    const w = mount(App, { props: { data, hydration: hyd } });
    await flushPromises();
    expect(new URLSearchParams(window.location.search).get("doc")).toBe("NEVER ARRIVES");

    hyd.loading = false;
    await flushPromises();

    expect(new URLSearchParams(window.location.search).has("doc")).toBe(false);
    expect(isDetail(w)).toBe(false);
  });

  it("does not clamp ?page= against a partial corpus, then clamps when complete", async () => {
    window.history.replaceState(null, "", "/?page=999");
    const original = window.innerHeight;
    Object.defineProperty(window, "innerHeight", { value: 400, configurable: true });
    try {
      const hyd = reactive(hydration({ loading: true, total: 60 }));
      const w = mount(App, { props: { data: many, hydration: hyd } });
      await flushPromises();
      expect(new URLSearchParams(window.location.search).get("page")).toBe("999");

      hyd.loading = false;
      await flushPromises();

      expect(w.text()).toContain("Page 6 of 6");
      expect(new URLSearchParams(window.location.search).get("page")).toBe("6");
    } finally {
      Object.defineProperty(window, "innerHeight", { value: original, configurable: true });
    }
  });

  it("hurries the load along when the user searches", async () => {
    const requestAll = vi.fn();
    const w = mount(App, {
      props: { data, hydration: hydration({ loading: true, total: 99, requestAll }) },
    });
    requestAll.mockClear();

    await w.find('input[type="search"]').setValue("brochure");
    await flushPromises();

    expect(requestAll).toHaveBeenCalled();
  });
});

describe("on-demand detail fields", () => {
  it("fetches the detail record when a document is opened and fills the panel in", async () => {
    const loadDetail = vi.fn(
      async (): Promise<DetailRecord> => ({
        r: "CCRI 2",
        abstract: "A late-arriving abstract.",
      }),
    );
    const w = mount(App, { props: { data, loadDetail } });

    await w.find(".document a").trigger("click");
    await flushPromises();

    // Position in the corpus is what addresses the detail shard.
    expect(loadDetail).toHaveBeenCalledWith(0, "CCRI 2");
    expect(w.text()).toContain("A late-arriving abstract.");
  });

  // A failed summary shard leaves a hole, after which array index and corpus
  // position disagree. The position stamped on by the loader is authoritative —
  // using indexOf here would address the wrong detail shard for every document
  // after the hole.
  it("addresses the detail shard by corpus position, not array index", async () => {
    const holed: IndexData = {
      title: "Holed",
      documents: [
        { ...data.documents[0], pos: 0 },
        // its shard failed, so this one sits at array index 1 but position 5000
        { ...data.documents[1], pos: 5000 },
      ],
    };
    const loadDetail = vi.fn(async (): Promise<DetailRecord | null> => null);
    const w = mount(App, { props: { data: holed, loadDetail } });

    const links = w.findAll(".document a");
    await links[links.length - 1].trigger("click");
    await flushPromises();

    expect(loadDetail).toHaveBeenCalledWith(5000, "CCRI 10");
  });

  it("asks for each document at most once", async () => {
    const loadDetail = vi.fn(async (): Promise<DetailRecord | null> => null);
    const w = mount(App, { props: { data, loadDetail } });

    await w.find(".document a").trigger("click");
    await flushPromises();
    await w.find('[aria-label="Back to index"]').trigger("click");
    await flushPromises();
    await w.find(".document a").trigger("click");
    await flushPromises();

    expect(loadDetail).toHaveBeenCalledTimes(1);
  });

  it("renders the summary fields when no detail shard is available", async () => {
    const w = mount(App, { props: { data } });
    await w.find(".document a").trigger("click");
    await flushPromises();

    expect(w.find('[aria-label="Back to index"]').exists()).toBe(true);
    expect(w.text()).toContain("Second meeting");
  });

  // loadSearchShards emits a NEW array each batch, carrying the previous
  // batches' element objects forward. Detail fields are merged into one of those
  // objects, and each document is only ever fetched once — so if a later batch
  // replaced the objects rather than re-listing them, an open panel would
  // silently lose its abstract with no second chance to refetch.
  it("keeps merged detail fields when a later shard batch arrives", async () => {
    const state = reactive<IndexData>({
      title: "Big Index",
      documents: data.documents.slice(0, 2),
    });
    const loadDetail = vi.fn(
      async (): Promise<DetailRecord> => ({
        r: "CCRI 2",
        abstract: "Merged before the next batch.",
      }),
    );
    const w = mount(App, {
      props: { data: state, hydration: hydration({ loading: true, total: 3 }), loadDetail },
    });

    await w.find(".document a").trigger("click");
    await flushPromises();
    expect(w.text()).toContain("Merged before the next batch.");

    // A further shard lands: same element objects, plus a new one.
    state.documents = [...state.documents, data.documents[2]];
    await flushPromises();

    expect(w.text()).toContain("Merged before the next batch.");
    expect(loadDetail).toHaveBeenCalledTimes(1);
  });
});

describe("relations on the detail page", () => {
  const isDetail = (w: ReturnType<typeof mount>) =>
    w.find('[aria-label="Back to index"]').exists();

  // "SI Brochure" is in this dataset; "ISO 9999" is not.
  const withRelations = (): DetailRecord => ({
    r: "CCRI 2",
    relations: [
      { type: "obsoletedBy", id: "SI Brochure" },
      { type: "updates", id: "ISO 9999" },
    ],
  });

  it("navigates to the related document when its link is clicked", async () => {
    const loadDetail = vi.fn(async () => withRelations());
    const w = mount(App, { props: { data, loadDetail } });

    await w.find(".document a").trigger("click");
    await flushPromises();

    const link = w.findAll("a").find((a) => a.text() === "SI Brochure");
    expect(link).toBeDefined();
    await link!.trigger("click");
    await flushPromises();

    expect(isDetail(w)).toBe(true);
    expect(w.text()).toContain("The SI");
    expect(decodeURIComponent(window.location.pathname)).toBe("/doc/SI Brochure");
  });

  it("leaves a target outside the dataset unlinked but visible", async () => {
    const loadDetail = vi.fn(async () => withRelations());
    const w = mount(App, { props: { data, loadDetail } });

    await w.find(".document a").trigger("click");
    await flushPromises();

    expect(w.findAll("a").map((a) => a.text())).not.toContain("ISO 9999");
    expect(w.text()).toContain("ISO 9999");
  });

  // While summary shards are still arriving the corpus is incomplete, so a real
  // intra-dataset target can look absent. Hurry the load rather than render it
  // permanently as plain text.
  it("hurries the shard load when the opened document has relations", async () => {
    const requestAll = vi.fn();
    const loadDetail = vi.fn(async () => withRelations());
    const w = mount(App, {
      props: { data, loadDetail, hydration: reactive(hydration({ loading: true, requestAll })) },
    });

    await w.find(".document a").trigger("click");
    await flushPromises();

    expect(requestAll).toHaveBeenCalled();
  });
});

// The corpus loads progressively, so a relation target can be genuinely present
// yet not loaded yet. Resolution reads a computed id set through the `hasDoc`
// predicate, so the link must appear on its own once the shard carrying the
// target lands — without reopening the detail panel.
describe("relation links upgrade as the corpus loads", () => {
  it("turns a plain-text target into a link when its shard arrives", async () => {
    const partial: IndexData = reactive({
      title: "Loading",
      documents: [{ ...data.documents[0], pos: 0 }],
    });
    const loadDetail = vi.fn(
      async (): Promise<DetailRecord> => ({
        r: "CCRI 2",
        relations: [{ type: "obsoletedBy", id: "SI Brochure" }],
      }),
    );
    const w = mount(App, { props: { data: partial, loadDetail } });

    await w.find(".document a").trigger("click");
    await flushPromises();

    // Target not loaded yet -> shown, but not a link.
    expect(w.text()).toContain("SI Brochure");
    expect(w.findAll("a").map((a) => a.text())).not.toContain("SI Brochure");

    // A later shard delivers it.
    partial.documents.push({ ...data.documents[2], pos: 1 });
    await flushPromises();

    expect(w.findAll("a").map((a) => a.text())).toContain("SI Brochure");
  });
});
