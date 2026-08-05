<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import type { IndexData } from "./lib/types";
import {
  applyFilters,
  distinctValues,
  type SortDir,
  type SortKey,
} from "./lib/filter";
import DocumentRow from "./components/DocumentRow.vue";

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
// ~8k docs) — only the current page is rendered to the DOM at a time.
const PAGE_SIZE = 100;
const page = ref(1);
const pageCount = computed(() => Math.max(1, Math.ceil(visible.value.length / PAGE_SIZE)));
const paged = computed(() => {
  const start = (page.value - 1) * PAGE_SIZE;
  return visible.value.slice(start, start + PAGE_SIZE);
});
// Reset to the first page whenever the filtered set changes.
watch([query, activeDoctypes, activeStages, sortKey, sortDir], () => {
  page.value = 1;
});
function goto(p: number) {
  page.value = Math.min(pageCount.value, Math.max(1, p));
  document.getElementById("relaton-index-app")?.scrollIntoView({ block: "start" });
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
onMounted(() => window.addEventListener("keydown", onKey));
onUnmounted(() => window.removeEventListener("keydown", onKey));
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
          <span v-if="isDark" aria-hidden="true">☀️</span>
          <span v-else aria-hidden="true">🌙</span>
        </button>
      </div>
    </header>

    <main class="mx-auto max-w-5xl px-4 py-6">
      <!-- Toolbar -->
      <div class="sticky top-0 z-10 -mx-4 mb-4 bg-slate-50/90 px-4 py-3 backdrop-blur dark:bg-slate-950/90">
        <div class="flex flex-wrap items-center gap-3">
          <div class="relative min-w-56 flex-1">
            <span class="pointer-events-none absolute inset-y-0 left-3 flex items-center text-slate-400">🔎</span>
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
              {{ k }}<span v-if="sortKey === k">{{ sortDir === "asc" ? " ↑" : " ↓" }}</span>
            </button>
          </div>

          <div class="flex items-center gap-1 rounded-lg border border-slate-300 p-0.5 dark:border-slate-700">
            <button
              type="button"
              class="rounded-md px-2 py-1 text-sm"
              :class="view === 'list' ? 'bg-brand text-white' : 'text-slate-600 dark:text-slate-300'"
              aria-label="List view"
              @click="setView('list')"
            >☰</button>
            <button
              type="button"
              class="rounded-md px-2 py-1 text-sm"
              :class="view === 'grid' ? 'bg-brand text-white' : 'text-slate-600 dark:text-slate-300'"
              aria-label="Grid view"
              @click="setView('grid')"
            >▦</button>
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

      <!-- List -->
      <div
        v-if="visible.length"
        :class="view === 'grid'
          ? 'grid grid-cols-1 gap-3 sm:grid-cols-2'
          : 'flex flex-col divide-y divide-slate-200 dark:divide-slate-800'"
      >
        <DocumentRow
          v-for="doc in paged"
          :key="doc.id + '|' + (doc.yaml ?? '')"
          :doc="doc"
          :view="view"
        />
      </div>
      <p v-else class="py-16 text-center text-slate-500 dark:text-slate-400">
        No documents match your filters.
      </p>

      <!-- Pagination -->
      <nav
        v-if="pageCount > 1"
        class="mt-6 flex items-center justify-center gap-2 text-sm"
        aria-label="Pagination"
      >
        <button
          type="button"
          class="rounded-md border border-slate-300 px-3 py-1 disabled:opacity-40 dark:border-slate-700"
          :disabled="page === 1"
          @click="goto(page - 1)"
        >Prev</button>
        <span class="text-slate-500 dark:text-slate-400">Page {{ page }} of {{ pageCount }}</span>
        <button
          type="button"
          class="rounded-md border border-slate-300 px-3 py-1 disabled:opacity-40 dark:border-slate-700"
          :disabled="page === pageCount"
          @click="goto(page + 1)"
        >Next</button>
      </nav>
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
