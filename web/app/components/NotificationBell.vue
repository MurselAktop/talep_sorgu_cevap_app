<script setup lang="ts">
const props = defineProps<{
  refreshKey?: number
}>()

const supabase = useSupabase()
const { user } = useAuth()
const { openConversation } = useDmPanel()

const open = ref(false)
const loading = ref(false)
const items = ref<any[]>([])
const rootEl = ref<HTMLElement | null>(null)

const unreadCount = computed(() => items.value.filter((n) => !n.is_read).length)

async function load() {
  if (!user.value) return
  loading.value = true
  try {
    const { data } = await supabase
      .from('notifications')
      .select('id, message, is_read, created_at, request_id, conversation_id')
      .order('created_at', { ascending: false })
      .limit(30)
    items.value = data || []
  } finally {
    loading.value = false
  }
}

watch(() => props.refreshKey, () => { void load() })

function toggle() {
  open.value = !open.value
  if (open.value) void load()
}

async function onTap(n: any) {
  if (!n.is_read) {
    await supabase.from('notifications').update({ is_read: true }).eq('id', n.id)
    n.is_read = true
  }
  open.value = false
  if (n.conversation_id) {
    openConversation(String(n.conversation_id))
    return
  }
  if (n.request_id) {
    await navigateTo(`/requests/${n.request_id}`)
  }
}

function onDocClick(e: MouseEvent) {
  if (!open.value || !rootEl.value) return
  if (!rootEl.value.contains(e.target as Node)) open.value = false
}

onMounted(() => {
  void load()
  document.addEventListener('click', onDocClick)
})
onUnmounted(() => document.removeEventListener('click', onDocClick))

// Sayfa değişince / odaklanınca taze sayım
const route = useRoute()
watch(() => route.path, () => { void load() })
</script>

<template>
  <div ref="rootEl" class="relative">
    <button
      type="button"
      class="relative flex h-9 w-9 items-center justify-center rounded-lg border border-gray-300 text-gray-600 hover:bg-gray-100 dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-700"
      title="Bildirimler"
      aria-label="Bildirimler"
      @click.stop="toggle"
    >
      <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
        <path d="M13.73 21a2 2 0 0 1-3.46 0" />
      </svg>
      <span
        v-if="unreadCount > 0"
        class="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold leading-none text-white"
      >
        {{ unreadCount > 99 ? '99+' : unreadCount }}
      </span>
    </button>

    <div
      v-if="open"
      class="absolute right-0 z-50 mt-2 w-[min(22rem,calc(100vw-2rem))] overflow-hidden rounded-xl border border-gray-200 bg-white shadow-xl dark:border-gray-700 dark:bg-gray-800"
      @click.stop
    >
      <div class="flex items-center justify-between border-b border-gray-200 px-3 py-2.5 dark:border-gray-700">
        <p class="text-[13px] font-semibold text-gray-900 dark:text-white">Bildirimler</p>
        <span v-if="unreadCount > 0" class="text-[11px] text-blue-600 dark:text-blue-400">
          {{ unreadCount }} okunmamış
        </span>
      </div>
      <div class="max-h-80 overflow-y-auto">
        <p v-if="loading" class="px-3 py-6 text-center text-xs text-gray-500">Yükleniyor…</p>
        <button
          v-for="n in items"
          :key="n.id"
          type="button"
          class="flex w-full gap-2 border-b border-gray-100 px-3 py-2.5 text-left last:border-0 hover:bg-gray-50 dark:border-gray-700/60 dark:hover:bg-gray-700/40"
          @click="onTap(n)"
        >
          <span
            class="mt-1.5 h-2 w-2 shrink-0 rounded-full"
            :class="n.is_read ? 'bg-transparent' : 'bg-blue-500'"
          />
          <div class="min-w-0 flex-1">
            <p
              class="text-[12px] leading-4 text-gray-800 dark:text-gray-100"
              :class="n.is_read ? 'font-normal text-gray-500 dark:text-gray-400' : 'font-semibold'"
            >
              {{ n.message }}
            </p>
            <p class="mt-0.5 text-[10px] text-gray-400">
              {{ new Date(n.created_at).toLocaleString('tr-TR') }}
            </p>
          </div>
        </button>
        <p v-if="!loading && !items.length" class="px-3 py-8 text-center text-xs text-gray-500">
          Hiç bildiriminiz yok.
        </p>
      </div>
    </div>
  </div>
</template>
