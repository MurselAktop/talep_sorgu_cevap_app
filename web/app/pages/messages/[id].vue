<script setup lang="ts">
const route = useRoute()
const { canViewIncoming } = useAuth()
const { openPanel, openConversation } = useDmPanel()

const id = String(route.params.id || '')

if (!canViewIncoming.value) {
  await navigateTo('/home')
} else {
  if (id) openConversation(id)
  else openPanel()
  await navigateTo('/home')
}
</script>

<template>
  <div />
</template>
