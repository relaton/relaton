// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import App from "./App.vue";
import type { IndexData } from "./lib/types";

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

  it("opens the detail view and sets ?doc= when a row is clicked", async () => {
    const w = mount(App, { props: { data } });
    // The first row's DocID link.
    await w.find(".document a").trigger("click");
    await flushPromises();

    expect(isDetail(w)).toBe(true);
    expect(w.find('input[type="search"]').exists()).toBe(false);
    expect(new URLSearchParams(window.location.search).get("doc")).toBe("CCRI 2");
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
