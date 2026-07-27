<script setup lang="ts">
/**
 * Eski /messages URL'leri hâlâ bookmark'larda olabilir —
 * ana sayfaya alıp sağ DM panelini açıyoruz.
 */
const { canViewIncoming } = useAuth()
const { openPanel } = useDmPanel()

if (!canViewIncoming.value) {
  await navigateTo('/home')
} else {
  openPanel()
  await navigateTo('/home')
}
</script>

<template>
  <div />
</template>
