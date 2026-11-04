// @vitest-environment happy-dom
import { describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
import Icon from "./Icon.vue";

describe("Icon", () => {
  it("renders an inline SVG with a path for a known name", () => {
    const w = mount(Icon, { props: { name: "search" } });
    const svg = w.find("svg");
    expect(svg.exists()).toBe(true);
    expect(svg.find("path").exists()).toBe(true);
  });

  it("uses the CalConnect Heroicons-outline style", () => {
    const svg = mount(Icon, { props: { name: "search" } }).find("svg");
    expect(svg.attributes("stroke")).toBe("currentColor");
    expect(svg.attributes("fill")).toBe("none");
    expect(svg.attributes("viewBox")).toBe("0 0 24 24");
    // Decorative — the parent control carries the accessible label.
    expect(svg.attributes("aria-hidden")).toBe("true");
  });

  it("renders nothing for an unknown name", () => {
    const w = mount(Icon, { props: { name: "not-a-real-icon" } });
    expect(w.find("svg").exists()).toBe(false);
  });

  it("passes a caller-supplied class through to the svg root", () => {
    const w = mount(Icon, { props: { name: "sun" }, attrs: { class: "h-5 w-5" } });
    const svg = w.find("svg");
    expect(svg.classes()).toContain("h-5");
    expect(svg.classes()).toContain("w-5");
  });

  it("provides every icon the UI references", () => {
    const names = [
      "sun", "moon", "search", "chevron-up", "chevron-down",
      "list", "grid", "copy", "check", "document",
    ];
    for (const name of names) {
      expect(mount(Icon, { props: { name } }).find("path").exists()).toBe(true);
    }
  });
});
