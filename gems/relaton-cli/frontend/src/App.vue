<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import type { IndexData } from "./lib/types";
import {
  applyFilters,
  distinctValues,
  type SortDir,
  type SortKey,
} from "./lib/filter";
import DocumentRow from "./components/DocumentRow.vue";
import DocumentDetail from "./components/DocumentDetail.vue";
import Pagination from "./components/Pagination.vue";
import Icon from "./components/Icon.vue";
import {
  readDocFromUrl,
  readPageFromUrl,
  writeDocToUrl,
  writePageToUrl,
} from "./lib/url";

const props = defineProps<{ data: IndexData }>();

const query = ref("");
const activeDoctypes = ref<Set<string>>(new Set());
const activeStages = ref<Set<string>>(new Set());
const sortKey = ref<SortKey>("id");
const sortDir = ref<SortDir>("asc");
const view = ref<"list" | "grid">(
  (localStorage.getItem("relaton-index-view") as "list" | "grid") || "list",
);
const isDark = ref(document.documentElement.classList.contains("dark"));
const searchEl = ref<HTMLInputElement | null>(null);

const docs = computed(() => props.data.documents);
const doctypes = computed(() => distinctValues(docs.value, "doctype"));
const stages = computed(() => distinctValues(docs.value, "stage"));

// Detail-page routing: `?doc=<id>` selects a document to show in full instead of
// the list. A missing/unknown id falls back to the list. This is the second
// piece of URL-synced state alongside `?page=N` (see lib/url.ts).
const selectedId = ref<string | null>(readDocFromUrl());
const selectedDoc = computed(() =>
  selectedId.value == null
    ? null
    : (docs.value.find((d) => d.id === selectedId.value) ?? null),
);
function openDoc(id: string) {
  selectedId.value = id;
  // New history entry so Back returns to the list at the same page.
  writeDocToUrl(id, "push");
  window.scrollTo({ top: 0 });
}
function closeDoc() {
  selectedId.value = null;
  // Replace (not push) so we don't leave a forward "detail" entry that Forward
  // would re-open; the list entry we opened from stays behind us for Back.
  writeDocToUrl(null, "replace");
}

const visible = computed(() =>
  applyFilters(docs.value, {
    query: query.value,
    doctypes: activeDoctypes.value,
    stages: activeStages.value,
    sortKey: sortKey.value,
    sortDir: sortDir.value,
  }),
);

// Client-side pagination keeps rendering fast for large indexes (e.g. BIPM's
// ~8k docs) — only the current page is rendered to the DOM at a time. The page
// size adapts to the viewport so a page fills roughly one screen instead of a
// fixed 100 rows. Row heights are estimates (px); grid packs two columns wide.
const listEl = ref<HTMLElement | null>(null);
const ROW_H = { list: 76, grid: 128 };
const RESERVE = 120; // bottom pagination + breathing room below the list
const MIN_ROWS = 10;
const MAX_ROWS = 100;

function computePageSize(): number {
  const vh = window.innerHeight || 800;
  const top = listEl.value?.getBoundingClientRect().top ?? 300;
  const avail = Math.max(vh - top - RESERVE, ROW_H.list);
  const cols = view.value === "grid" && window.innerWidth >= 640 ? 2 : 1;
  const rows = Math.floor(avail / ROW_H[view.value]) * cols;
  return Math.min(MAX_ROWS, Math.max(MIN_ROWS, rows));
}

const pageSize = ref(computePageSize());
// The current page is reflected in the URL (?page=N) so reload/share/bookmark
// preserves it; restore it here on load (clamped to a valid page after the
// adaptive pageSize settles — see onMounted).
const page = ref(readPageFromUrl());
const pageCount = computed(() => Math.max(1, Math.ceil(visible.value.length / pageSize.value)));
const paged = computed(() => {
  const start = (page.value - 1) * pageSize.value;
  return visible.value.slice(start, start + pageSize.value);
});

function refreshPageSize() {
  const next = computePageSize();
  if (next !== pageSize.value) pageSize.value = next;
}
let resizeTimer: ReturnType<typeof setTimeout> | undefined;
function onResize() {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(refreshPageSize, 150);
}
// Grid/list density differs, so recompute when the view mode changes.
watch(view, () => nextTick(refreshPageSize));
// The list is unmounted while a detail page is open (listEl is null, so the page
// size can't be measured); re-measure once we return to the list. A stale/unknown
// `?doc=` id (whose doc isn't found) resolves to no detail — drop the param so the
// URL matches the list we actually show. `immediate` handles an unknown id present
// at load time (a deep link to a since-removed doc).
watch(
  selectedDoc,
  (doc) => {
    if (doc) return;
    if (selectedId.value != null) {
      selectedId.value = null;
      writeDocToUrl(null, "replace");
    }
    nextTick(refreshPageSize);
  },
  { immediate: true },
);
// Keep the current page valid after the page size changes (e.g. on resize).
watch(pageSize, () => {
  const clamped = Math.min(page.value, pageCount.value);
  if (clamped !== page.value) {
    page.value = clamped;
    writePageToUrl(clamped, "replace");
  }
});
// Reset to the first page whenever the filtered set changes.
watch([query, activeDoctypes, activeStages, sortKey, sortDir], () => {
  if (page.value !== 1) {
    page.value = 1;
    writePageToUrl(1, "replace");
  }
});
function goto(p: number) {
  const next = Math.min(pageCount.value, Math.max(1, p));
  if (next !== page.value) {
    page.value = next;
    // User navigation → a new history entry so Back/Forward walk pages.
    writePageToUrl(next, "push");
  }
  document.getElementById("relaton-index-app")?.scrollIntoView({ block: "start" });
}
// Back/Forward navigation: sync both the open detail doc and the page from the
// URL without writing them back (which would otherwise clobber the history
// entry we just navigated to).
function onPopState() {
  selectedId.value = readDocFromUrl();
  page.value = Math.min(pageCount.value, Math.max(1, readPageFromUrl()));
}

function toggle(set: Set<string>, value: string): Set<string> {
  const next = new Set(set);
  next.has(value) ? next.delete(value) : next.add(value);
  return next;
}
function toggleDoctype(v: string) {
  activeDoctypes.value = toggle(activeDoctypes.value, v);
}
function toggleStage(v: string) {
  activeStages.value = toggle(activeStages.value, v);
}
function clearFilters() {
  query.value = "";
  activeDoctypes.value = new Set();
  activeStages.value = new Set();
}

function setSort(key: SortKey) {
  if (sortKey.value === key) {
    sortDir.value = sortDir.value === "asc" ? "desc" : "asc";
  } else {
    sortKey.value = key;
    sortDir.value = "asc";
  }
}

function setView(v: "list" | "grid") {
  view.value = v;
  localStorage.setItem("relaton-index-view", v);
}

function toggleTheme() {
  isDark.value = !isDark.value;
  document.documentElement.classList.toggle("dark", isDark.value);
  try {
    localStorage.setItem("relaton-index-theme", isDark.value ? "dark" : "light");
  } catch {
    /* ignore */
  }
}

const hasFilters = computed(
  () =>
    query.value.trim() !== "" ||
    activeDoctypes.value.size > 0 ||
    activeStages.value.size > 0,
);

function onKey(e: KeyboardEvent) {
  const target = e.target as HTMLElement | null;
  const typing =
    target &&
    (target.tagName === "INPUT" ||
      target.tagName === "TEXTAREA" ||
      target.isContentEditable);
  if (e.key === "/" && !typing) {
    e.preventDefault();
    searchEl.value?.focus();
  } else if (e.key === "Escape" && target === searchEl.value) {
    query.value = "";
    searchEl.value?.blur();
  }
}
onMounted(() => {
  window.addEventListener("keydown", onKey);
  window.addEventListener("resize", onResize);
  window.addEventListener("popstate", onPopState);
  // Measure the real layout once rows have rendered, then size the page. Only
  // then is pageCount final, so clamp a URL-provided page (e.g. ?page=99, or a
  // smaller viewport with fewer pages) and normalize the URL in place.
  nextTick(() => {
    refreshPageSize();
    const clamped = Math.min(page.value, pageCount.value);
    if (clamped !== page.value) {
      page.value = clamped;
      writePageToUrl(clamped, "replace");
    }
  });
});
onUnmounted(() => {
  window.removeEventListener("keydown", onKey);
  window.removeEventListener("resize", onResize);
  window.removeEventListener("popstate", onPopState);
  clearTimeout(resizeTimer);
});
</script>

<template>
  <div class="min-h-screen bg-slate-50 text-slate-900 dark:bg-slate-950 dark:text-slate-100">
    <header class="border-b border-slate-200 dark:border-slate-800">
      <div class="mx-auto flex max-w-5xl items-center justify-between gap-4 px-4 py-5">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">{{ data.title }}</h1>
          <p class="mt-1 text-sm text-slate-500 dark:text-slate-400">
            Please use the provided Relaton DocID to refer to an item.
          </p>
        </div>
        <button
          type="button"
          class="rounded-lg border border-slate-300 p-2 text-slate-600 hover:bg-slate-100 dark:border-slate-700 dark:text-slate-300 dark:hover:bg-slate-800"
          :aria-label="isDark ? 'Switch to light theme' : 'Switch to dark theme'"
          :title="isDark ? 'Light theme' : 'Dark theme'"
          @click="toggleTheme"
        >
          <Icon :name="isDark ? 'sun' : 'moon'" class="h-5 w-5" />
        </button>
      </div>
    </header>

    <main class="mx-auto max-w-5xl px-4 py-6">
      <DocumentDetail v-if="selectedDoc" :doc="selectedDoc" @back="closeDoc" />
      <template v-else>
      <!-- Toolbar -->
      <div class="sticky top-0 z-10 -mx-4 mb-4 bg-slate-50/90 px-4 py-3 backdrop-blur dark:bg-slate-950/90">
        <div class="flex flex-wrap items-center gap-3">
          <div class="relative min-w-56 flex-1">
            <span class="pointer-events-none absolute inset-y-0 left-3 flex items-center text-slate-400">
              <Icon name="search" class="h-4 w-4" />
            </span>
            <input
              ref="searchEl"
              v-model="query"
              type="search"
              class="w-full rounded-lg border border-slate-300 bg-white py-2 pl-9 pr-3 text-sm shadow-sm outline-none focus:border-brand focus:ring-2 focus:ring-brand/30 dark:border-slate-700 dark:bg-slate-900"
              aria-label="Filter documents by identifier or title"
              placeholder="Filter by identifier or title…  ( / )"
            />
          </div>

          <div class="flex items-center gap-1 text-sm">
            <span class="text-slate-500 dark:text-slate-400">Sort</span>
            <button
              v-for="k in (['id', 'date', 'title'] as SortKey[])"
              :key="k"
              type="button"
              class="rounded-md px-2 py-1 capitalize"
              :class="sortKey === k
                ? 'bg-brand text-white'
                : 'text-slate-600 hover:bg-slate-200 dark:text-slate-300 dark:hover:bg-slate-800'"
              @click="setSort(k)"
            >
              {{ k }}<Icon
                v-if="sortKey === k"
                :name="sortDir === 'asc' ? 'chevron-up' : 'chevron-down'"
                class="ml-0.5 inline h-3.5 w-3.5"
              />
            </button>
          </div>

          <div class="flex items-center gap-1 rounded-lg border border-slate-300 p-0.5 dark:border-slate-700">
            <button
              type="button"
              class="rounded-md px-2 py-1 text-sm"
              :class="view === 'list' ? 'bg-brand text-white' : 'text-slate-600 dark:text-slate-300'"
              aria-label="List view"
              @click="setView('list')"
            ><Icon name="list" class="h-4 w-4" /></button>
            <button
              type="button"
              class="rounded-md px-2 py-1 text-sm"
              :class="view === 'grid' ? 'bg-brand text-white' : 'text-slate-600 dark:text-slate-300'"
              aria-label="Grid view"
              @click="setView('grid')"
            ><Icon name="grid" class="h-4 w-4" /></button>
          </div>
        </div>

        <!-- Facets -->
        <div v-if="doctypes.length || stages.length" class="mt-3 flex flex-wrap items-center gap-2">
          <button
            v-for="t in doctypes"
            :key="'dt-' + t"
            type="button"
            class="rounded-full border px-3 py-1 text-xs"
            :class="activeDoctypes.has(t)
              ? 'border-brand bg-brand text-white'
              : 'border-slate-300 text-slate-600 hover:border-brand dark:border-slate-700 dark:text-slate-300'"
            @click="toggleDoctype(t)"
          >{{ t }}</button>
          <button
            v-for="s in stages"
            :key="'st-' + s"
            type="button"
            class="rounded-full border px-3 py-1 text-xs"
            :class="activeStages.has(s)
              ? 'border-emerald-500 bg-emerald-500 text-white'
              : 'border-slate-300 text-slate-600 hover:border-emerald-500 dark:border-slate-700 dark:text-slate-300'"
            @click="toggleStage(s)"
          >{{ s }}</button>
        </div>

        <div class="mt-3 flex items-center gap-3 text-xs text-slate-500 dark:text-slate-400">
          <span>{{ visible.length }} of {{ docs.length }} documents</span>
          <button
            v-if="hasFilters"
            type="button"
            class="text-brand hover:underline dark:text-brand-dark"
            @click="clearFilters"
          >Clear filters</button>
        </div>
      </div>

      <!-- Pagination (top, mirrors the bottom controls) -->
      <Pagination class="mb-4" :page="page" :page-count="pageCount" @go="goto" />

      <!-- List -->
      <div
        v-if="visible.length"
        ref="listEl"
        :class="view === 'grid'
          ? 'grid grid-cols-1 gap-3 sm:grid-cols-2'
          : 'flex flex-col divide-y divide-slate-200 dark:divide-slate-800'"
      >
        <DocumentRow
          v-for="doc in paged"
          :key="doc.id + '|' + (doc.yaml ?? '')"
          :doc="doc"
          :view="view"
          @open="openDoc"
        />
      </div>
      <p v-else class="py-16 text-center text-slate-500 dark:text-slate-400">
        No documents match your filters.
      </p>

      <!-- Pagination (bottom) -->
      <Pagination class="mt-6" :page="page" :page-count="pageCount" @go="goto" />
      </template>
    </main>

    <footer class="border-t border-slate-200 py-8 text-center text-xs text-slate-500 dark:border-slate-800 dark:text-slate-400">
      <p>
        An open source project by
        <a class="text-brand hover:underline dark:text-brand-dark" href="https://www.ribose.com">Ribose</a>.
        Built with
        <a class="text-brand hover:underline dark:text-brand-dark" href="https://www.relaton.org">Relaton</a>.
      </p>
      <p v-if="data.generated" class="mt-1">Generated {{ data.generated }}</p>
    </footer>
  </div>
</template>
