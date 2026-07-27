<script setup lang="ts">
const props = defineProps<{
  src?: string | null
  alt?: string
}>()

const open = ref(false)

function show() {
  if (!props.src) return
  open.value = true
}

function hide() {
  open.value = false
}

function onKey(e: KeyboardEvent) {
  if (e.key === 'Escape') hide()
}

watch(open, (v) => {
  if (!import.meta.client) return
  if (v) document.addEventListener('keydown', onKey)
  else document.removeEventListener('keydown', onKey)
})

onUnmounted(() => {
  if (import.meta.client) document.removeEventListener('keydown', onKey)
})

defineExpose({ show, hide })
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="open && src"
        class="fixed inset-0 z-[100] flex items-center justify-center bg-black/92 p-4"
        role="dialog"
        aria-modal="true"
        aria-label="Profil fotoğrafı"
        @click.self="hide"
      >
        <button
          type="button"
          class="absolute right-4 top-4 flex h-10 w-10 items-center justify-center rounded-full bg-white/10 text-white hover:bg-white/20"
          title="Kapat"
          @click="hide"
        >
          <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M18 6 6 18M6 6l12 12" />
          </svg>
        </button>
        <img
          :src="src"
          :alt="alt || 'Profil'"
          class="max-h-[min(90vh,900px)] max-w-[min(92vw,900px)] rounded-2xl object-contain shadow-2xl"
          @click.stop
        />
      </div>
    </Transition>
  </Teleport>
</template>
