<script setup lang="ts">
const props = defineProps<{ value: number; duration?: number }>()
const display = ref(0)

watch(
  () => props.value,
  (target) => {
    const from = display.value
    const to = Number(target) || 0
    const duration = props.duration ?? 900
    const start = performance.now()
    function tick(now: number) {
      const t = Math.min(1, (now - start) / duration)
      const eased = 1 - Math.pow(1 - t, 3)
      display.value = Math.round(from + (to - from) * eased)
      if (t < 1) requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
  },
  { immediate: true },
)
</script>

<template>
  <span>{{ display.toLocaleString('tr-TR') }}</span>
</template>
