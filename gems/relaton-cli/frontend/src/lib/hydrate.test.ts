// @vitest-environment happy-dom
import { afterEach, describe, expect, it } from "vitest";
import { resolveIndexData } from "./hydrate";
import type { IndexData } from "./types";

afterEach(() => {
  delete window.RELATON_INDEX_DATA;
  document.body.innerHTML = "";
});

describe("resolveIndexData", () => {
  it("reads window.RELATON_INDEX_DATA (embedded mode)", async () => {
    window.RELATON_INDEX_DATA = {
      title: "T",
      documents: [
        { id: "A 1", title: "One", doctype: "x", stage: null, date: "2020-01-01", link: null, yaml: "a.yaml" },
      ],
    } as IndexData;
    const el = document.createElement("div");
    const data = await resolveIndexData(el);
    expect(data.title).toBe("T");
    expect(data.documents).toHaveLength(1);
    expect(data.documents[0].id).toBe("A 1");
  });

  it("parses the crawler DOM data-* attributes (dom mode)", async () => {
    const el = document.createElement("div");
    el.dataset.title = "DomTitle";
    el.innerHTML = `
      <div class="documents">
        <article class="document" data-id="B 2" data-title="Two"
                 data-doctype="report" data-stage="published"
                 data-date="2021-02-02" data-href="b.yaml" data-link="http://x"></article>
      </div>`;
    const data = await resolveIndexData(el);
    expect(data.title).toBe("DomTitle");
    expect(data.documents).toHaveLength(1);
    expect(data.documents[0]).toMatchObject({
      id: "B 2",
      title: "Two",
      doctype: "report",
      stage: "published",
      date: "2021-02-02",
      yaml: "b.yaml",
      link: "http://x",
    });
  });

  it("prefers the embedded description over the mount-node one", async () => {
    window.RELATON_INDEX_DATA = {
      title: "T",
      description: "From JSON",
      documents: [],
    } as IndexData;
    const el = document.createElement("div");
    el.dataset.description = "From DOM";
    const data = await resolveIndexData(el);
    expect(data.description).toBe("From JSON");
  });

  it("falls back to the mount-node data-description", async () => {
    window.RELATON_INDEX_DATA = { title: "T", documents: [] } as IndexData;
    const el = document.createElement("div");
    el.dataset.description = "From DOM";
    const data = await resolveIndexData(el);
    expect(data.description).toBe("From DOM");
  });

  it("reads data-description in dom mode", async () => {
    const el = document.createElement("div");
    el.dataset.description = "A blurb";
    el.innerHTML = `
      <div class="documents">
        <article class="document" data-id="B 2" data-title="Two"></article>
      </div>`;
    const data = await resolveIndexData(el);
    expect(data.description).toBe("A blurb");
  });

  it("leaves the description null when none is given", async () => {
    const el = document.createElement("div");
    el.innerHTML = `
      <div class="documents">
        <article class="document" data-id="B 2" data-title="Two"></article>
      </div>`;
    const data = await resolveIndexData(el);
    expect(data.description).toBeNull();
  });

  it("returns an empty set when there is no data", async () => {
    const el = document.createElement("div");
    const data = await resolveIndexData(el);
    expect(data.documents).toEqual([]);
  });
});
