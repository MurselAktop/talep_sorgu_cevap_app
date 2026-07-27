<script setup lang="ts">
const { isDark, apply } = useTheme()

function onChange(e: Event) {
  const checked = (e.target as HTMLInputElement).checked
  apply(checked ? 'dark' : 'light')
}
</script>

<template>
  <label
    class="inline-flex cursor-pointer items-center"
    :title="isDark ? 'Açık temaya geç' : 'Koyu temaya geç'"
  >
    <span class="sr-only">Tema</span>
    <input
      type="checkbox"
      class="peer sr-only"
      :checked="isDark"
      @change="onChange"
    />
    <span
      class="relative inline-flex h-7 w-12 items-center rounded-full border border-gray-300 bg-gray-200 shadow-inner transition-colors peer-focus-visible:ring-2 peer-focus-visible:ring-blue-500/40 peer-checked:border-blue-500/50 peer-checked:bg-blue-600 dark:border-gray-600 dark:bg-gray-700 dark:peer-checked:bg-blue-600"
    >
      <span
        class="absolute left-0.5 flex h-6 w-6 items-center justify-center rounded-full bg-white text-amber-500 shadow transition-transform duration-200 dark:text-indigo-600"
        :class="isDark ? 'translate-x-5 text-indigo-600' : 'translate-x-0'"
      >
        <!-- moon when dark -->
        <svg v-if="isDark" class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="currentColor">
          <path d="M21 14.5A8.5 8.5 0 1 1 9.5 3 7 7 0 0 0 21 14.5z" />
        </svg>
        <!-- sun when light -->
        <svg v-else class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <circle cx="12" cy="12" r="3.5" />
          <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41" />
        </svg>
      </span>
    </span>
  </label>
</template>
