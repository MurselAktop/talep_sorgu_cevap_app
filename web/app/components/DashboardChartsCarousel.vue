<script setup lang="ts">
/**
 * Dashboard grafikleri — yuvarlak sekme butonları + yatay kaydırma (touchpad/trackpad).
 */
const props = defineProps<{
  slides: { id: string; label: string; short: string }[]
}>()

const active = ref(0)
const scroller = ref<HTMLElement | null>(null)
let scrollLock = false
let wheelAccum = 0
let wheelTimer: ReturnType<typeof setTimeout> | null = null

watch(
  () => props.slides.length,
  () => {
    active.value = 0
    nextTick(() => goTo(0, false))
  },
)

function goTo(index: number, smooth = true) {
  const el = scroller.value
  if (!el || index < 0 || index >= props.slides.length) return
  active.value = index
  scrollLock = true
  const slide = el.children[index] as HTMLElement | undefined
  if (slide) {
    el.scrollTo({ left: slide.offsetLeft, behavior: smooth ? 'smooth' : 'auto' })
  }
  window.setTimeout(() => { scrollLock = false }, 380)
}

function onScroll() {
  if (scrollLock) return
  const el = scroller.value
  if (!el || !el.children.length) return
  const mid = el.scrollLeft + el.clientWidth / 2
  let best = 0
  let bestDist = Infinity
  for (let i = 0; i < el.children.length; i++) {
    const child = el.children[i] as HTMLElement
    const center = child.offsetLeft + child.clientWidth / 2
    const dist = Math.abs(center - mid)
    if (dist < bestDist) {
      bestDist = dist
      best = i
    }
  }
  if (best !== active.value) active.value = best
}

/**
 * Touchpad: yatay delta biriktirip eşik aşınca sekme değiştir.
 * Dikey sayfa kaydırmasını bozmaz (yalnızca belirgin yatay / Shift+dikey).
 */
function onWheel(e: WheelEvent) {
  if (props.slides.length < 2) return

  const absX = Math.abs(e.deltaX)
  const absY = Math.abs(e.deltaY)
  const horizontal = absX > absY && absX > 2
  const shiftVertical = e.shiftKey && absY > absX

  if (!horizontal && !shiftVertical) return

  e.preventDefault()
  const delta = horizontal ? e.deltaX : e.deltaY
  wheelAccum += delta

  if (wheelTimer) clearTimeout(wheelTimer)
  wheelTimer = setTimeout(() => { wheelAccum = 0 }, 180)

  const threshold = 40
  if (wheelAccum > threshold) {
    wheelAccum = 0
    goTo(Math.min(active.value + 1, props.slides.length - 1))
  } else if (wheelAccum < -threshold) {
    wheelAccum = 0
    goTo(Math.max(active.value - 1, 0))
  }
}

onMounted(() => {
  nextTick(() => {
    goTo(0, false)
    scroller.value?.addEventListener('wheel', onWheel, { passive: false })
  })
})

onUnmounted(() => {
  scroller.value?.removeEventListener('wheel', onWheel)
  if (wheelTimer) clearTimeout(wheelTimer)
})
</script>

<template>
  <div class="card overflow-hidden p-0">
    <!-- Yuvarlak sekme butonları -->
    <div class="flex flex-wrap items-center justify-center gap-2 border-b border-gray-200/80 px-4 py-3 dark:border-gray-700/80">
      <button
        v-for="(s, i) in slides"
        :key="s.id"
        type="button"
        class="rounded-full px-3.5 py-1.5 text-[11px] font-semibold transition-all duration-150"
        :class="active === i
          ? 'bg-blue-600 text-white shadow-[0_4px_12px_rgba(37,99,235,0.35)]'
          : 'bg-gray-200/80 text-gray-600 hover:bg-gray-300/80 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600'"
        @click="goTo(i)"
      >
        {{ s.short }}
      </button>
    </div>

    <div class="flex items-center justify-between gap-3 px-4 pt-3">
      <h2 class="min-w-0 truncate text-[13px] font-semibold text-gray-900 dark:text-white">
        {{ slides[active]?.label }}
      </h2>
      <div class="flex shrink-0 items-center gap-1.5">
        <button
          type="button"
          class="flex h-7 w-7 items-center justify-center rounded-full border border-gray-300 text-gray-500 hover:bg-gray-100 disabled:opacity-30 dark:border-gray-600 dark:hover:bg-gray-700"
          :disabled="active <= 0"
          title="Önceki"
          @click="goTo(active - 1)"
        >
          <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
            <path d="M15 18l-6-6 6-6" />
          </svg>
        </button>
        <span class="min-w-[2.5rem] text-center text-[11px] text-gray-400">
          {{ active + 1 }}/{{ slides.length }}
        </span>
        <button
          type="button"
          class="flex h-7 w-7 items-center justify-center rounded-full border border-gray-300 text-gray-500 hover:bg-gray-100 disabled:opacity-30 dark:border-gray-600 dark:hover:bg-gray-700"
          :disabled="active >= slides.length - 1"
          title="Sonraki"
          @click="goTo(active + 1)"
        >
          <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
            <path d="M9 18l6-6-6-6" />
          </svg>
        </button>
      </div>
    </div>

    <!-- Kaydırılabilir slaytlar -->
    <div
      ref="scroller"
      class="flex touch-pan-x snap-x snap-mandatory overflow-x-auto scroll-smooth pb-4 pt-2 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      @scroll.passive="onScroll"
    >
      <div
        v-for="(s, i) in slides"
        :key="s.id"
        class="w-full min-w-full shrink-0 snap-center px-4"
      >
        <slot :name="s.id" :active="active === i" :play-key="`${s.id}-${active === i ? active : 'off'}`" />
      </div>
    </div>

    <!-- Alt nokta göstergesi -->
    <div class="flex justify-center gap-1.5 pb-3">
      <button
        v-for="(s, i) in slides"
        :key="`dot-${s.id}`"
        type="button"
        class="h-2 rounded-full transition-all duration-200"
        :class="active === i ? 'w-5 bg-blue-600' : 'w-2 bg-gray-300 dark:bg-gray-600'"
        :aria-label="s.label"
        @click="goTo(i)"
      />
    </div>
  </div>
</template>
