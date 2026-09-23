import { describe, expect, it } from "vitest";
import { applyFilters, compareDocuments, distinctValues, matchesQuery } from "./filter";
import type { IndexDocument } from "./types";

const doc = (over: Partial<IndexDocument>): IndexDocument => ({
  id: "X 1",
  title: "Title",
  doctype: null,
  stage: null,
  date: null,
  link: null,
  yaml: null,
  ...over,
});

const docs: IndexDocument[] = [
  doc({ id: "CCRI 2", title: "Second meeting", doctype: "meeting-report", stage: "published", date: "2009-06-19" }),
  doc({ id: "CCRI 10", title: "Tenth meeting", doctype: "meeting-report", stage: "draft", date: "2019-01-01" }),
  doc({ id: "SI Brochure", title: "The SI", doctype: "brochure", stage: "published", date: "2019-05-20" }),
];

describe("matchesQuery", () => {
  it("matches all terms case-insensitively", () => {
    expect(matchesQuery(docs[0], "second CCRI")).toBe(true);
    expect(matchesQuery(docs[0], "brochure")).toBe(false);
    expect(matchesQuery(docs[0], "")).toBe(true);
  });
});

describe("distinctValues", () => {
  it("returns sorted distinct non-empty values", () => {
    expect(distinctValues(docs, "doctype")).toEqual(["brochure", "meeting-report"]);
    expect(distinctValues(docs, "stage")).toEqual(["draft", "published"]);
  });
});

describe("compareDocuments", () => {
  it("sorts ids naturally (2 before 10)", () => {
    expect(compareDocuments(docs[0], docs[1], "id", "asc")).toBeLessThan(0);
  });
  it("reverses on desc", () => {
    expect(compareDocuments(docs[0], docs[1], "id", "desc")).toBeGreaterThan(0);
  });
});

describe("applyFilters", () => {
  it("filters by facet and sorts", () => {
    const out = applyFilters(docs, {
      query: "",
      doctypes: new Set(["meeting-report"]),
      stages: new Set(),
      sortKey: "id",
      sortDir: "asc",
    });
    expect(out.map((d) => d.id)).toEqual(["CCRI 2", "CCRI 10"]);
  });

  it("combines search + stage facet", () => {
    const out = applyFilters(docs, {
      query: "meeting",
      doctypes: new Set(),
      stages: new Set(["published"]),
      sortKey: "date",
      sortDir: "asc",
    });
    expect(out.map((d) => d.id)).toEqual(["CCRI 2"]);
  });
});

describe("date sort with missing dates", () => {
  it("sorts undated documents last in both directions", () => {
    const docs = [
      doc({ id: "undated-a", title: "x" }),
      doc({ id: "dated-2020", title: "x", date: "2020-01-01" }),
      doc({ id: "undated-b", title: "x" }),
      doc({ id: "dated-1999", title: "x", date: "1999-01-01" }),
    ];
    const opts = (sortDir: SortDir) => ({
      query: "", doctypes: new Set(), stages: new Set(),
      sortKey: "date" as const, sortDir,
    });
    expect(applyFilters(docs, opts("asc")).map((d) => d.id))
      .toEqual(["dated-1999", "dated-2020", "undated-a", "undated-b"]);
    expect(applyFilters(docs, opts("desc")).map((d) => d.id))
      .toEqual(["dated-2020", "dated-1999", "undated-a", "undated-b"]);
  });
});
