<script setup lang="ts">
const props = defineProps<{
  page: number
  pageCount: number
}>()

const emit = defineEmits<{
  'update:page': [number]
}>()

const pages = computed(() => {
  const total = props.pageCount
  const current = props.page
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1)
  const set = new Set<number>([1, total, current - 1, current, current + 1].filter((p) => p >= 1 && p <= total))
  return Array.from(set).sort((a, b) => a - b)
})

function go(p: number) {
  if (p < 1 || p > props.pageCount || p === props.page) return
  emit('update:page', p)
}
</script>

<template>
  <div v-if="pageCount > 1" class="flex flex-wrap items-center justify-center gap-1 pt-4">
    <button
      type="button"
      class="btn-secondary px-3 py-1.5 text-xs"
      :disabled="page <= 1"
      @click="go(page - 1)"
    >
      ‹ Önceki
    </button>
    <template v-for="(p, i) in pages" :key="p">
      <span v-if="i > 0 && p - pages[i - 1]! > 1" class="px-1 text-gray-400">…</span>
      <button
        type="button"
        class="min-w-9 rounded-lg px-2.5 py-1.5 text-xs font-medium transition-colors duration-150"
        :class="p === page
          ? 'bg-blue-600 text-white'
          : 'text-gray-600 hover:bg-gray-200 dark:text-gray-300 dark:hover:bg-gray-700'"
        @click="go(p)"
      >
        {{ p }}
      </button>
    </template>
    <button
      type="button"
      class="btn-secondary px-3 py-1.5 text-xs"
      :disabled="page >= pageCount"
      @click="go(page + 1)"
    >
      Sonraki ›
    </button>
  </div>
</template>
