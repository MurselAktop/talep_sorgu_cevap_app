<script setup lang="ts">
defineProps<{
  status?: string | null
}>()
</script>

<template>
  <span
    class="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium"
    :class="{
      'bg-amber-500/20 text-amber-400': status === 'acik',
      'bg-blue-500/20 text-blue-400': status === 'cozuldu',
      'bg-teal-500/20 text-teal-400': status === 'onaylandi',
      'bg-red-500/20 text-red-400': status === 'reddedildi',
      'bg-gray-500/20 text-gray-400': !status || status === 'iptal',
    }"
  >
    {{ statusLabels[status || ''] || status || '—' }}
  </span>
</template>
