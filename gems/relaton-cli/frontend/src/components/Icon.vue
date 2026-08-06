<script setup lang="ts">
import { computed } from "vue";

// Inline Heroicons-outline SVG paths, matching the icon set used on
// https://standards.calconnect.org/standards/ (fill=none, stroke=currentColor,
// 24×24). Keeping the geometry here — instead of an icon dependency — mirrors
// how CalConnect inlines the same paths, so the icons inherit text colour and
// dark mode for free. Callers size the icon with a passthrough class (h-5 w-5…)
// and provide the accessible label on the surrounding control; the glyph itself
// stays aria-hidden.
const PATHS: Record<string, string[]> = {
  sun: [
    "M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z",
  ],
  moon: [
    "M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z",
  ],
  search: ["M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"],
  "chevron-up": ["M5 15l7-7 7 7"],
  "chevron-down": ["M19 9l-7 7-7-7"],
  list: ["M4 6h16M4 12h16M4 18h16"],
  grid: [
    "M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z",
  ],
  copy: [
    "M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z",
  ],
  check: ["M5 13l4 4L19 7"],
  document: [
    "M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z",
  ],
};

const props = defineProps<{ name: string }>();
const paths = computed(() => PATHS[props.name] ?? null);
</script>

<template>
  <svg
    v-if="paths"
    xmlns="http://www.w3.org/2000/svg"
    fill="none"
    stroke="currentColor"
    stroke-width="2"
    stroke-linecap="round"
    stroke-linejoin="round"
    viewBox="0 0 24 24"
    aria-hidden="true"
  >
    <path v-for="(d, i) in paths" :key="i" :d="d" />
  </svg>
</template>
