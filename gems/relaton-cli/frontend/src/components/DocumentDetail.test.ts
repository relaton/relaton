// @vitest-environment happy-dom
import { describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
import DocumentDetail from "./DocumentDetail.vue";
import type { IndexDocument } from "../lib/types";

const rich: IndexDocument = {
  id: "ISO 1234:2020",
  title: "A standard about things",
  doctype: "international-standard",
  stage: "published",
  date: "2020-05-01",
  link: "https://www.iso.org/standard/1234.html",
  yaml: "https://raw.example/data/iso-1234.yaml",
  abstract: "This document specifies the things.",
  edition: "2",
  languages: ["en", "fr"],
  keywords: ["metrology", "units"],
  publisher: "International Organization for Standardization",
  contributors: [
    { name: "International Organization for Standardization", role: "publisher" },
    { name: "Ada Lovelace", role: "author" },
  ],
  docids: [
    { id: "ISO 1234:2020", type: "ISO", language: "en" },
    { id: "10.1000/xyz", type: "DOI" },
  ],
  dates: [
    { type: "published", value: "2020-05-01" },
    { type: "created", value: "2019" },
  ],
};

const minimal: IndexDocument = {
  id: "RAW 9",
  title: "Just a title",
  doctype: null,
  stage: null,
  date: null,
  link: null,
  yaml: null,
};

describe("DocumentDetail", () => {
  it("renders the id, title and all enriched fields", () => {
    const w = mount(DocumentDetail, { props: { doc: rich } });
    const text = w.text();
    expect(text).toContain("ISO 1234:2020");
    expect(text).toContain("A standard about things");
    expect(text).toContain("This document specifies the things.");
    expect(text).toContain("Ada Lovelace");
    expect(text).toContain("author");
    expect(text).toContain("International Organization for Standardization");
    expect(text).toContain("10.1000/xyz");
    expect(text).toContain("metrology");
    expect(text).toContain("2019");
    expect(text).toContain("published");
  });

  it("links to the landing page and the raw YAML source", () => {
    const w = mount(DocumentDetail, { props: { doc: rich } });
    const hrefs = w.findAll("a").map((a) => a.attributes("href"));
    expect(hrefs).toContain("https://www.iso.org/standard/1234.html");
    expect(hrefs).toContain("https://raw.example/data/iso-1234.yaml");
  });

  it("emits back when the Back control is clicked", async () => {
    const w = mount(DocumentDetail, { props: { doc: rich } });
    await w.get('[aria-label="Back to index"]').trigger("click");
    expect(w.emitted("back")).toBeTruthy();
  });

  it("degrades gracefully when only summary fields are present", () => {
    const w = mount(DocumentDetail, { props: { doc: minimal } });
    const text = w.text();
    expect(text).toContain("RAW 9");
    expect(text).toContain("Just a title");
    // No enriched sections leak in.
    expect(text).not.toContain("Abstract");
    expect(text).not.toContain("Contributors");
    expect(text).not.toContain("Identifiers");
  });
});
