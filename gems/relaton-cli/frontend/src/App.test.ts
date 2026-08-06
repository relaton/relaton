// @vitest-environment happy-dom
import { beforeEach, describe, expect, it } from "vitest";
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

beforeEach(() => {
  // A mount node is expected to exist (goto() scrolls it into view).
  document.body.innerHTML = '<div id="relaton-index-app"></div>';
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
    const many: IndexData = {
      title: "Big Index",
      documents: Array.from({ length: 60 }, (_, i) => ({
        id: `DOC ${i + 1}`, title: `Title ${i + 1}`,
        doctype: "report", stage: "published", date: "2020-01-01",
        link: null, yaml: `d/${i + 1}.yaml`,
      })),
    };
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
