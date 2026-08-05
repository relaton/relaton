// @vitest-environment happy-dom
import { beforeEach, describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
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
});
