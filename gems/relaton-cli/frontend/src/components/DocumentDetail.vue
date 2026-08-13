<script setup lang="ts">
import { computed, ref } from "vue";
import type { IndexDocument } from "../lib/types";
import { docHref } from "../lib/url";
import Icon from "./Icon.vue";

const props = defineProps<{
  doc: IndexDocument;
  // Does this DocID exist in the current dataset? Deliberately a predicate
  // rather than a Set: App builds that set from the whole corpus, which is
  // expensive at 166k documents, and passing the built value would materialize
  // it for every detail panel — including the majority that have no relations.
  // A function stays lazy while still registering the reactive dependency, so
  // unresolved targets upgrade from plain text to links as summary shards land.
  hasDoc?: (id: string) => boolean;
}>();
defineEmits<{ back: []; open: [id: string] }>();

const copied = ref(false);
async function copyId() {
  try {
    await navigator.clipboard.writeText(props.doc.id);
    copied.value = true;
    setTimeout(() => (copied.value = false), 1200);
  } catch {
    /* clipboard may be blocked; ignore */
  }
}

// Each optional block renders only when it has content, so a summary-only
// document (dom / static-json modes, which don't carry the detail fields) shows
// just the header, core metadata and links — nothing empty leaks in.
const languages = computed(() => (props.doc.languages ?? []).join(", "));
const keywords = computed(() => props.doc.keywords ?? []);
const contributors = computed(() => props.doc.contributors ?? []);
const docids = computed(() => props.doc.docids ?? []);
const dates = computed(() => props.doc.dates ?? []);
// The single summary date is only worth showing when the full date list is
// absent (e.g. a summary-only build), to avoid duplicating the Dates section.
const showSummaryDate = computed(() => !!props.doc.date && dates.value.length === 0);
const hasMeta = computed(
  () =>
    !!(
      props.doc.doctype ||
      props.doc.stage ||
      props.doc.edition ||
      languages.value ||
      props.doc.publisher ||
      showSummaryDate.value
    ),
);

function docidLabel(d: { type?: string | null; language?: string | null }): string {
  return [d.type, d.language].filter(Boolean).join(" · ");
}

// Relations, each paired with whether its target is a document in this dataset.
// A target that isn't (it may live in another relaton-data repo) is still listed
// — just as plain text, so nothing links to a page that doesn't exist here.
const relations = computed(() =>
  (props.doc.relations ?? []).map((r) => ({
    ...r,
    label: relationLabel(r.type),
    href: props.hasDoc?.(r.id) ? docHref(r.id) : null,
  })),
);

// "obsoletedBy" -> "Obsoleted by"; "partOf" -> "Part of".
function relationLabel(type?: string | null): string {
  if (!type) return "Related";
  const words = type.replace(/([a-z0-9])([A-Z])/g, "$1 $2").toLowerCase();
  return words.charAt(0).toUpperCase() + words.slice(1);
}
</script>

<template>
  <article class="py-2">
    <button
      type="button"
      class="mb-6 inline-flex items-center gap-1.5 text-sm text-brand hover:underline dark:text-brand-dark"
      aria-label="Back to index"
      @click="$emit('back')"
    >
      <Icon name="arrow-left" class="h-4 w-4" />Back to index
    </button>

    <header class="mb-6">
      <div class="flex items-center gap-2">
        <h2 class="font-mono text-lg font-semibold text-brand dark:text-brand-dark">
          {{ doc.id }}
        </h2>
        <button
          type="button"
          class="rounded p-0.5 text-slate-400 transition hover:text-brand"
          :aria-label="`Copy DocID ${doc.id}`"
          :title="copied ? 'Copied!' : 'Copy DocID'"
          @click="copyId"
        >
          <Icon :name="copied ? 'check' : 'copy'" class="h-4 w-4" />
        </button>
      </div>
      <h1 class="mt-1 text-2xl font-semibold tracking-tight">{{ doc.title }}</h1>
    </header>

    <section v-if="doc.abstract" class="mb-6">
      <h3 class="mb-1 text-sm font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
        Abstract
      </h3>
      <p class="text-sm leading-relaxed text-slate-700 dark:text-slate-300">{{ doc.abstract }}</p>
    </section>

    <section v-if="hasMeta" class="mb-6">
      <dl class="grid grid-cols-1 gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
        <div v-if="doc.doctype" class="flex gap-2">
          <dt class="w-28 shrink-0 text-slate-500 dark:text-slate-400">Type</dt>
          <dd>{{ doc.doctype }}</dd>
        </div>
        <div v-if="doc.stage" class="flex gap-2">
          <dt class="w-28 shrink-0 text-slate-500 dark:text-slate-400">Stage</dt>
          <dd>{{ doc.stage }}</dd>
        </div>
        <div v-if="doc.edition" class="flex gap-2">
          <dt class="w-28 shrink-0 text-slate-500 dark:text-slate-400">Edition</dt>
          <dd>{{ doc.edition }}</dd>
        </div>
        <div v-if="languages" class="flex gap-2">
          <dt class="w-28 shrink-0 text-slate-500 dark:text-slate-400">Language</dt>
          <dd>{{ languages }}</dd>
        </div>
        <div v-if="doc.publisher" class="flex gap-2">
          <dt class="w-28 shrink-0 text-slate-500 dark:text-slate-400">Publisher</dt>
          <dd>{{ doc.publisher }}</dd>
        </div>
        <div v-if="showSummaryDate" class="flex gap-2">
          <dt class="w-28 shrink-0 text-slate-500 dark:text-slate-400">Date</dt>
          <dd>{{ doc.date }}</dd>
        </div>
      </dl>
    </section>

    <section v-if="keywords.length" class="mb-6">
      <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
        Keywords
      </h3>
      <div class="flex flex-wrap gap-1.5">
        <span
          v-for="k in keywords"
          :key="k"
          class="rounded-full bg-slate-100 px-3 py-1 text-xs text-slate-600 dark:bg-slate-800 dark:text-slate-300"
        >{{ k }}</span>
      </div>
    </section>

    <section v-if="contributors.length" class="mb-6">
      <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
        Contributors
      </h3>
      <ul class="space-y-1 text-sm">
        <li v-for="(c, i) in contributors" :key="i" class="flex flex-wrap items-baseline gap-2">
          <span class="text-slate-700 dark:text-slate-300">{{ c.name }}</span>
          <span v-if="c.role" class="text-xs text-slate-500 dark:text-slate-400">{{ c.role }}</span>
        </li>
      </ul>
    </section>

    <section v-if="docids.length" class="mb-6">
      <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
        Identifiers
      </h3>
      <ul class="space-y-1 text-sm">
        <li v-for="(d, i) in docids" :key="i" class="flex flex-wrap items-baseline gap-2">
          <span class="font-mono text-slate-700 dark:text-slate-300">{{ d.id }}</span>
          <span v-if="docidLabel(d)" class="text-xs text-slate-500 dark:text-slate-400">{{ docidLabel(d) }}</span>
        </li>
      </ul>
    </section>

    <section v-if="relations.length" class="mb-6">
      <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
        Relations
      </h3>
      <ul class="space-y-1 text-sm">
        <li v-for="(r, i) in relations" :key="i" class="flex flex-wrap items-baseline gap-2">
          <span class="w-28 shrink-0 text-slate-500 dark:text-slate-400">{{ r.label }}</span>
          <!-- A real ?doc= anchor whose plain click App.vue turns into an
               in-page navigation. `.exact` leaves modified clicks (Cmd/Ctrl/Shift
               = open in new tab/window) to the browser, so the href stays useful. -->
          <a
            v-if="r.href"
            :href="r.href"
            class="font-mono text-brand hover:underline dark:text-brand-dark"
            @click.exact.prevent="$emit('open', r.id)"
          >{{ r.id }}</a>
          <span v-else class="font-mono text-slate-700 dark:text-slate-300">{{ r.id }}</span>
        </li>
      </ul>
    </section>

    <section v-if="dates.length" class="mb-6">
      <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
        Dates
      </h3>
      <ul class="space-y-1 text-sm">
        <li v-for="(d, i) in dates" :key="i" class="flex flex-wrap items-baseline gap-2">
          <span v-if="d.type" class="text-slate-500 dark:text-slate-400">{{ d.type }}</span>
          <time class="text-slate-700 dark:text-slate-300">{{ d.value }}</time>
        </li>
      </ul>
    </section>

    <section v-if="doc.link || doc.yaml" class="flex flex-wrap gap-4 text-sm">
      <a
        v-if="doc.link"
        :href="doc.link"
        target="_blank"
        rel="noopener"
        class="inline-flex items-center gap-1 text-brand hover:underline dark:text-brand-dark"
      ><Icon name="external" class="h-4 w-4" />Landing page</a>
      <a
        v-if="doc.yaml"
        :href="doc.yaml"
        target="_blank"
        rel="noopener"
        class="inline-flex items-center gap-1 text-brand hover:underline dark:text-brand-dark"
      ><Icon name="document" class="h-4 w-4" />Raw YAML</a>
    </section>
  </article>
</template>
