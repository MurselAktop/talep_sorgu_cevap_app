<script setup lang="ts">
defineProps<{
  name: string
  active?: boolean
}>()
</script>

<template>
  <svg
    class="h-4 w-4 shrink-0"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="1.75"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    <template v-if="name === 'home'">
      <path d="M3 10.5 12 3l9 7.5" />
      <path d="M5 10v10h14V10" />
    </template>
    <template v-else-if="name === 'requests'">
      <path d="M8 6h13M8 12h13M8 18h13" />
      <path d="M3 6h.01M3 12h.01M3 18h.01" />
    </template>
    <template v-else-if="name === 'people'">
      <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="4" />
      <path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" />
    </template>
    <template v-else-if="name === 'reports'">
      <path d="M4 19V5M4 19h16" />
      <path d="M8 17V9M12 17V7M16 17v-4" />
    </template>
    <template v-else-if="name === 'settings'">
      <circle cx="12" cy="12" r="3" />
      <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </template>
    <template v-else-if="name === 'create'">
      <path d="M12 5v14M5 12h14" />
    </template>
    <template v-else-if="name === 'messages'">
      <path d="M21 15a4 4 0 0 1-4 4H8l-5 3V7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4z" />
    </template>
    <template v-else-if="name === 'assistant'">
      <rect x="4" y="8" width="16" height="10" rx="2" />
      <path d="M9 8V6a3 3 0 0 1 6 0v2M9 14h.01M15 14h.01" />
    </template>
    <template v-else-if="name === 'profile'">
      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
      <circle cx="12" cy="7" r="4" />
    </template>
    <template v-else-if="name === 'logout'">
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <path d="M16 17l5-5-5-5M21 12H9" />
    </template>
    <template v-else>
      <circle cx="12" cy="12" r="9" />
      <path d="M9 12h6M12 9v6" />
    </template>
  </svg>
</template>
