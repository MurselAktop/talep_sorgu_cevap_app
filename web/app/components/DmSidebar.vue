<script setup lang="ts">
const { user, canViewIncoming } = useAuth()
const supabase = useSupabase()
const {
  open,
  conversationId,
  otherName,
  closePanel,
  openConversation,
  backToList,
  refreshUnread,
} = useDmPanel()

const conversations = ref<any[]>([])
const contacts = ref<any[]>([])
const messages = ref<any[]>([])
const loadingList = ref(false)
const loadingChat = ref(false)
const sending = ref(false)
const showNew = ref(false)
const body = ref('')
const listEl = ref<HTMLElement | null>(null)
let pollTimer: ReturnType<typeof setInterval> | null = null

function initials(name?: string | null) {
  const n = (name || '?').trim()
  const parts = n.split(/\s+/).filter(Boolean)
  if (parts.length >= 2) return (parts[0]![0]! + parts[1]![0]!).toUpperCase()
  return n.slice(0, 2).toUpperCase()
}

function lastPreview(c: any) {
  const text = (c.last_message_body || c.last_message || '').trim()
  if (!text) return 'Henüz mesaj yok'
  const mine = c.last_message_sender_id && user.value?.id && c.last_message_sender_id === user.value.id
  return mine ? `Siz: ${text}` : text
}

function relativeTime(iso?: string | null) {
  if (!iso) return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  const now = Date.now()
  const diff = Math.max(0, now - d.getTime())
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'şimdi'
  if (mins < 60) return `${mins} dk`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours} sa`
  const days = Math.floor(hours / 24)
  if (days === 1) return 'Dün'
  if (days < 7) return `${days} gün`
  return d.toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' })
}

async function loadConversations() {
  if (!canViewIncoming.value) return
  loadingList.value = true
  try {
    const { data } = await supabase.rpc('get_my_dm_conversations')
    conversations.value = Array.isArray(data) ? data : []
    await refreshUnread()
  } finally {
    loadingList.value = false
  }
}

async function loadContacts() {
  showNew.value = true
  const { data } = await supabase.rpc('get_dm_contacts')
  contacts.value = Array.isArray(data) ? data : []
}

async function startWith(contact: { id: string; full_name?: string }) {
  const { data, error } = await supabase.rpc('get_or_create_dm_conversation', {
    p_other_user_id: contact.id,
  })
  if (error) return
  const id = typeof data === 'string' ? data : data?.id || data
  showNew.value = false
  openConversation(String(id), contact.full_name || '')
}

async function loadMessages() {
  if (!conversationId.value) return
  loadingChat.value = true
  try {
    const { data } = await supabase
      .from('dm_messages')
      .select('id, body, sender_id, created_at, tagged_request_id')
      .eq('conversation_id', conversationId.value)
      .order('created_at', { ascending: true })
    messages.value = data || []
    await supabase.rpc('mark_dm_conversation_read', {
      p_conversation_id: conversationId.value,
    })
    await refreshUnread()
    await nextTick()
    if (listEl.value) listEl.value.scrollTop = listEl.value.scrollHeight
  } finally {
    loadingChat.value = false
  }
}

async function send() {
  const text = body.value.trim()
  if (!text || !conversationId.value || !user.value) return
  sending.value = true
  try {
    const { error } = await supabase.from('dm_messages').insert({
      conversation_id: conversationId.value,
      sender_id: user.value.id,
      body: text,
    })
    if (error) throw error
    body.value = ''
    await loadMessages()
  } finally {
    sending.value = false
  }
}

function pickConversation(c: any) {
  openConversation(
    String(c.conversation_id || c.id),
    c.other_full_name || c.other_user_name || 'Konuşma',
  )
}

watch(open, async (isOpen) => {
  if (pollTimer) {
    clearInterval(pollTimer)
    pollTimer = null
  }
  if (!isOpen) return
  if (conversationId.value) {
    await loadMessages()
    pollTimer = setInterval(loadMessages, 4000)
  } else {
    await loadConversations()
  }
})

watch(conversationId, async (id) => {
  if (!open.value) return
  if (pollTimer) {
    clearInterval(pollTimer)
    pollTimer = null
  }
  if (id) {
    await loadMessages()
    pollTimer = setInterval(loadMessages, 4000)
  } else {
    await loadConversations()
  }
})

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer)
})
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
        v-if="open && canViewIncoming"
        class="fixed inset-0 z-[60] bg-black/40 backdrop-blur-[1px]"
        @click="closePanel"
      />
    </Transition>

    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="translate-x-full"
      enter-to-class="translate-x-0"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="translate-x-0"
      leave-to-class="translate-x-full"
    >
      <aside
        v-if="open && canViewIncoming"
        class="fixed inset-y-0 right-0 z-[70] flex w-full max-w-md flex-col border-l border-gray-200/80 bg-white shadow-[-12px_0_40px_rgba(15,23,42,0.18)] dark:border-gray-700 dark:bg-gray-900 dark:shadow-[-12px_0_40px_rgba(0,0,0,0.5)]"
        role="dialog"
        aria-label="Mesajlar"
      >
        <!-- Header -->
        <div class="flex h-14 shrink-0 items-center gap-2 border-b border-gray-200/80 bg-gradient-to-r from-blue-600/10 to-transparent px-3 dark:border-gray-700 dark:from-blue-500/10">
          <button
            v-if="conversationId"
            type="button"
            class="rounded-xl p-2 text-gray-500 hover:bg-gray-200/70 dark:hover:bg-gray-800"
            title="Konuşmalara dön"
            @click="backToList"
          >
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M15 18l-6-6 6-6" />
            </svg>
          </button>
          <div class="min-w-0 flex-1">
            <p class="truncate text-[14px] font-semibold text-gray-900 dark:text-white">
              {{ conversationId ? (otherName || 'Sohbet') : 'Mesajlar' }}
            </p>
            <p class="text-[11px] text-gray-500">
              {{ conversationId ? 'Kurum içi sohbet' : `${conversations.length} konuşma` }}
            </p>
          </div>
          <button
            v-if="!conversationId"
            type="button"
            class="btn-primary px-3 py-1.5 text-xs shadow-md shadow-blue-500/25"
            @click="loadContacts"
          >
            Yeni
          </button>
          <button
            type="button"
            class="rounded-xl p-2 text-gray-500 hover:bg-gray-200/70 dark:hover:bg-gray-800"
            title="Kapat"
            @click="closePanel"
          >
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M18 6 6 18M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Conversation list -->
        <div v-if="!conversationId" class="flex min-h-0 flex-1 flex-col overflow-hidden">
          <div
            v-if="showNew"
            class="shrink-0 border-b border-gray-200 bg-slate-50 p-3 dark:border-gray-700 dark:bg-gray-800/50"
          >
            <div class="mb-2 flex items-center justify-between">
              <p class="text-xs font-semibold text-gray-600 dark:text-gray-300">Yeni konuşma</p>
              <button type="button" class="text-xs text-blue-600" @click="showNew = false">Kapat</button>
            </div>
            <div class="max-h-44 space-y-1.5 overflow-y-auto">
              <button
                v-for="c in contacts"
                :key="c.id"
                type="button"
                class="flex w-full items-center gap-2.5 rounded-xl border border-gray-200/80 bg-white px-3 py-2 text-left transition hover:border-blue-400/40 hover:bg-blue-50/50 dark:border-gray-700 dark:bg-gray-900 dark:hover:bg-blue-950/30"
                @click="startWith(c)"
              >
                <span class="flex h-8 w-8 items-center justify-center rounded-full bg-blue-600/15 text-[11px] font-bold text-blue-600 dark:text-blue-300">
                  {{ initials(c.full_name) }}
                </span>
                <span class="min-w-0 flex-1">
                  <span class="block truncate text-[13px] font-medium text-gray-900 dark:text-gray-100">{{ c.full_name }}</span>
                  <span class="text-[11px] text-gray-500">{{ roleLabels[c.role] || c.role }}</span>
                </span>
              </button>
              <p v-if="!contacts.length" class="py-2 text-center text-xs text-gray-500">Kişi bulunamadı.</p>
            </div>
          </div>

          <div class="flex-1 overflow-y-auto px-2 py-2">
            <p v-if="loadingList" class="p-4 text-center text-xs text-gray-500">Yükleniyor…</p>
            <button
              v-for="c in conversations"
              :key="c.conversation_id || c.id"
              type="button"
              class="mb-1.5 flex w-full items-start gap-3 rounded-2xl px-3 py-3 text-left transition hover:bg-blue-600/[0.06] dark:hover:bg-blue-500/10"
              :class="Number(c.unread_count || 0) > 0 ? 'bg-blue-600/[0.05] dark:bg-blue-500/[0.08]' : ''"
              @click="pickConversation(c)"
            >
              <span
                class="relative flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-blue-500 to-blue-700 text-[12px] font-bold text-white shadow-md shadow-blue-500/25"
              >
                {{ initials(c.other_full_name || c.other_user_name) }}
                <span
                  v-if="Number(c.unread_count || 0) > 0"
                  class="absolute -right-0.5 -top-0.5 h-2.5 w-2.5 rounded-full bg-red-500 ring-2 ring-white dark:ring-gray-900"
                />
              </span>
              <span class="min-w-0 flex-1">
                <span class="flex items-center justify-between gap-2">
                  <span
                    class="truncate text-[13px] text-gray-900 dark:text-gray-100"
                    :class="Number(c.unread_count || 0) > 0 ? 'font-bold' : 'font-semibold'"
                  >
                    {{ c.other_full_name || c.other_user_name || 'Konuşma' }}
                  </span>
                  <span class="shrink-0 text-[10px] text-gray-400">
                    {{ relativeTime(c.last_message_at) }}
                  </span>
                </span>
                <span class="mt-0.5 flex items-center gap-2">
                  <span
                    class="min-w-0 flex-1 truncate text-[12px] leading-4"
                    :class="Number(c.unread_count || 0) > 0
                      ? 'font-medium text-gray-700 dark:text-gray-200'
                      : 'text-gray-500'"
                  >
                    {{ lastPreview(c) }}
                  </span>
                  <span
                    v-if="Number(c.unread_count || 0) > 0"
                    class="flex h-5 min-w-5 shrink-0 items-center justify-center rounded-full bg-blue-600 px-1.5 text-[10px] font-bold text-white"
                  >
                    {{ c.unread_count > 99 ? '99+' : c.unread_count }}
                  </span>
                </span>
              </span>
            </button>
            <div
              v-if="!loadingList && !conversations.length"
              class="mx-4 mt-10 rounded-2xl border border-dashed border-gray-300 px-4 py-8 text-center dark:border-gray-600"
            >
              <p class="text-[13px] font-medium text-gray-700 dark:text-gray-200">Henüz konuşma yok</p>
              <p class="mt-1 text-[11px] text-gray-500">“Yeni” ile bir kişi seçip sohbet başlatın.</p>
            </div>
          </div>
        </div>

        <!-- Chat -->
        <div v-else class="flex min-h-0 flex-1 flex-col bg-[radial-gradient(ellipse_at_top,_rgba(59,130,246,0.06),_transparent_55%)]">
          <div ref="listEl" class="flex-1 space-y-2 overflow-y-auto px-3 py-3">
            <p v-if="loadingChat && !messages.length" class="text-xs text-gray-500">Yükleniyor…</p>
            <div
              v-for="m in messages"
              :key="m.id"
              class="max-w-[85%] rounded-2xl px-3.5 py-2 text-[13px] leading-5 shadow-sm"
              :class="m.sender_id === user?.id
                ? 'ml-auto rounded-br-md bg-blue-600 text-white'
                : 'rounded-bl-md bg-white text-gray-800 ring-1 ring-gray-200/80 dark:bg-gray-800 dark:text-gray-100 dark:ring-gray-700'"
            >
              <p class="whitespace-pre-wrap">{{ m.body }}</p>
              <p
                class="mt-1 text-[10px]"
                :class="m.sender_id === user?.id ? 'text-blue-100' : 'text-gray-400'"
              >
                {{ new Date(m.created_at).toLocaleString('tr-TR') }}
              </p>
            </div>
            <p v-if="!loadingChat && !messages.length" class="text-xs text-gray-500">
              Henüz mesaj yok. İlk mesajı yazın.
            </p>
          </div>
          <form
            class="flex gap-2 border-t border-gray-200/80 bg-white/90 p-3 backdrop-blur dark:border-gray-700 dark:bg-gray-900/90"
            @submit.prevent="send"
          >
            <input
              v-model="body"
              class="flex-1 rounded-xl"
              placeholder="Mesaj yazın…"
              :disabled="sending"
            />
            <button class="btn-primary px-3" type="submit" :disabled="sending">
              Gönder
            </button>
          </form>
        </div>
      </aside>
    </Transition>
  </Teleport>
</template>
