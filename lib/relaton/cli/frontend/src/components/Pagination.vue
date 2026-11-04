<script setup lang="ts">
defineProps<{ page: number; pageCount: number }>();
const emit = defineEmits<{ go: [page: number] }>();
</script>

<template>
  <nav
    v-if="pageCount > 1"
    class="flex items-center justify-center gap-2 text-sm"
    aria-label="Pagination"
  >
    <button
      type="button"
      class="rounded-md border border-slate-300 px-3 py-1 disabled:opacity-40 dark:border-slate-700"
      :disabled="page === 1"
      @click="emit('go', page - 1)"
    >Prev</button>
    <span class="text-slate-500 dark:text-slate-400">Page {{ page }} of {{ pageCount }}</span>
    <button
      type="button"
      class="rounded-md border border-slate-300 px-3 py-1 disabled:opacity-40 dark:border-slate-700"
      :disabled="page === pageCount"
      @click="emit('go', page + 1)"
    >Next</button>
  </nav>
</template>
