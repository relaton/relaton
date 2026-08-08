<script setup lang="ts">
import { computed, ref } from "vue";
import type { IndexDocument } from "../lib/types";
import Icon from "./Icon.vue";

const props = defineProps<{ doc: IndexDocument; view: "list" | "grid" }>();
defineEmits<{ open: [id: string] }>();

// A real, shareable link to the detail page (?doc=<id>) — crawlable and
// middle-click/new-tab friendly — while a plain click is intercepted by App.vue
// to SPA-navigate (preserving the current ?page= etc.). Built with
// URLSearchParams so the encoding matches writeDocToUrl (lib/url.ts) exactly.
const detailHref = computed(
  () => `?${new URLSearchParams({ doc: props.doc.id }).toString()}`,
);

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
            <a
              :href="detailHref"
              class="hover:underline"
              @click.prevent="$emit('open', doc.id)"
            >{{ doc.id }}</a>
          </h2>
          <button
            type="button"
            class="rounded p-0.5 text-slate-400 opacity-0 transition group-hover:opacity-100 hover:text-brand"
            :aria-label="`Copy DocID ${doc.id}`"
            :title="copied ? 'Copied!' : 'Copy DocID'"
            @click="copyId(doc.id)"
          >
            <Icon :name="copied ? 'check' : 'copy'" class="h-4 w-4" />
          </button>
        </div>
        <p class="mt-1 text-sm text-slate-700 dark:text-slate-300">
          <a
            :href="detailHref"
            class="hover:underline"
            tabindex="-1"
            @click.prevent="$emit('open', doc.id)"
          >{{ doc.title }}</a>
        </p>
      </div>

      <div class="flex shrink-0 items-start gap-2">
        <div class="flex flex-col items-end gap-1 text-xs">
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
        </div>
        <a
          :href="detailHref"
          class="mt-0.5 text-slate-300 transition group-hover:text-brand dark:text-slate-600 dark:group-hover:text-brand-dark"
          aria-hidden="true"
          tabindex="-1"
          @click.prevent="$emit('open', doc.id)"
        ><Icon name="chevron-right" class="h-5 w-5" /></a>
      </div>
    </div>
  </article>
</template>
