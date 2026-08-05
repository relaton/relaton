<script setup lang="ts">
import { ref } from "vue";
import type { IndexDocument } from "../lib/types";

defineProps<{ doc: IndexDocument; view: "list" | "grid" }>();

const copied = ref(false);
async function copyId(id: string) {
  try {
    await navigator.clipboard.writeText(id);
    copied.value = true;
    setTimeout(() => (copied.value = false), 1200);
  } catch {
    /* clipboard may be blocked; ignore */
  }
}
</script>

<template>
  <article
    class="document group py-4"
    :class="view === 'grid'
      ? 'rounded-xl border border-slate-200 bg-white p-4 dark:border-slate-800 dark:bg-slate-900'
      : ''"
  >
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <div class="flex items-center gap-2">
          <h2 class="truncate font-mono text-sm font-semibold text-brand dark:text-brand-dark">
            <a v-if="doc.link" :href="doc.link" class="hover:underline">{{ doc.id }}</a>
            <span v-else>{{ doc.id }}</span>
          </h2>
          <button
            type="button"
            class="rounded p-0.5 text-slate-400 opacity-0 transition group-hover:opacity-100 hover:text-brand"
            :aria-label="`Copy DocID ${doc.id}`"
            :title="copied ? 'Copied!' : 'Copy DocID'"
            @click="copyId(doc.id)"
          >
            <span aria-hidden="true">{{ copied ? "✓" : "⧉" }}</span>
          </button>
        </div>
        <p class="mt-1 text-sm text-slate-700 dark:text-slate-300">{{ doc.title }}</p>
      </div>

      <div class="flex shrink-0 flex-col items-end gap-1 text-xs">
        <div class="flex flex-wrap justify-end gap-1">
          <span
            v-if="doc.doctype"
            class="rounded bg-slate-100 px-1.5 py-0.5 text-slate-600 dark:bg-slate-800 dark:text-slate-300"
          >{{ doc.doctype }}</span>
          <span
            v-if="doc.stage"
            class="rounded bg-emerald-100 px-1.5 py-0.5 text-emerald-700 dark:bg-emerald-900/50 dark:text-emerald-300"
          >{{ doc.stage }}</span>
        </div>
        <time v-if="doc.date" class="text-slate-400">{{ doc.date }}</time>
        <a
          v-if="doc.yaml"
          :href="doc.yaml"
          target="_blank"
          rel="noopener"
          class="text-brand hover:underline dark:text-brand-dark"
        >YAML</a>
      </div>
    </div>
  </article>
</template>
