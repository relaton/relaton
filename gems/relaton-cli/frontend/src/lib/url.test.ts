// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { readPageFromUrl, writePageToUrl } from "./url";

beforeEach(() => {
  // Start every test from a clean, param-free URL.
  window.history.replaceState(null, "", "/");
});

describe("readPageFromUrl", () => {
  it("parses a valid page param", () => {
    expect(readPageFromUrl("?page=3")).toBe(3);
  });

  it("falls back to 1 when the param is missing", () => {
    expect(readPageFromUrl("")).toBe(1);
    expect(readPageFromUrl("?foo=1")).toBe(1);
  });

  it("falls back to 1 for zero, negative, fractional, or non-numeric values", () => {
    expect(readPageFromUrl("?page=0")).toBe(1);
    expect(readPageFromUrl("?page=-2")).toBe(1);
    expect(readPageFromUrl("?page=2.5")).toBe(1);
    expect(readPageFromUrl("?page=abc")).toBe(1);
  });

  it("reads the page param alongside other params", () => {
    expect(readPageFromUrl("?foo=1&page=4")).toBe(4);
  });

  it("defaults to the live location when no search string is given", () => {
    window.history.replaceState(null, "", "/?page=7");
    expect(readPageFromUrl()).toBe(7);
  });
});

describe("writePageToUrl", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("sets ?page=N while preserving other params", () => {
    window.history.replaceState(null, "", "/?foo=bar");
    writePageToUrl(2);
    const params = new URLSearchParams(window.location.search);
    expect(params.get("page")).toBe("2");
    expect(params.get("foo")).toBe("bar");
  });

  it("deletes the page param for page 1 (clean canonical URL)", () => {
    window.history.replaceState(null, "", "/?page=5");
    writePageToUrl(1);
    expect(new URLSearchParams(window.location.search).has("page")).toBe(false);
  });

  it("uses replaceState by default", () => {
    const replace = vi.spyOn(window.history, "replaceState");
    const push = vi.spyOn(window.history, "pushState");
    writePageToUrl(3);
    expect(replace).toHaveBeenCalledTimes(1);
    expect(push).not.toHaveBeenCalled();
  });

  it("uses pushState when mode is 'push'", () => {
    const replace = vi.spyOn(window.history, "replaceState");
    const push = vi.spyOn(window.history, "pushState");
    writePageToUrl(3, "push");
    expect(push).toHaveBeenCalledTimes(1);
    expect(replace).not.toHaveBeenCalled();
  });
});
