<script setup lang="ts">
/**
 * Mobildeki gibi: personel/müdür/admin için mesaj FAB + sağ üstte turuncu asistan rozeti;
 * vatandaş için yalnız turuncu asistan FAB.
 */
const { canViewIncoming } = useAuth()
const { openPanel: openDmPanel, unreadTotal: dmUnread } = useDmPanel()
const { open: chatOpen, toggleChat, closeChat } = useAiAssistant()
const supabase = useSupabase()

const messages = ref<{ role: 'user' | 'model'; text: string; analysis?: any }[]>([])
const input = ref('')
const loading = ref(false)
const error = ref('')
const departments = ref<string[]>([])
const listEl = ref<HTMLElement | null>(null)

onMounted(async () => {
  const { data } = await supabase.from('departments').select('name').eq('is_active', true)
  departments.value = (data || []).map((d: any) => d.name)
})

watch(
  () => messages.value.length,
  async () => {
    await nextTick()
    if (listEl.value) listEl.value.scrollTop = listEl.value.scrollHeight
  },
)

async function send() {
  const text = input.value.trim()
  if (!text || loading.value) return
  error.value = ''
  messages.value.push({ role: 'user', text })
  input.value = ''
  loading.value = true
  try {
    const payload = {
      messages: messages.value.map((m) => ({
        role: m.role === 'model' ? 'model' : 'user',
        text: m.role === 'model' && m.analysis ? JSON.stringify(m.analysis) : m.text,
      })),
      departments: departments.value,
    }
    const { data, error: err } = await supabase.functions.invoke('analyze-request', { body: payload })
    // Edge Function hata gövdesi çoğu zaman `data.error` içinde gelir;
    // FunctionsHttpError mesajı generic kalabiliyor.
    const bodyError =
      data && typeof data === 'object' && typeof (data as any).error === 'string'
        ? (data as any).error as string
        : null
    if (err || bodyError) throw new Error(bodyError || err?.message || 'Asistan yanıt veremedi.')
    if (data?.error) throw new Error(String(data.error))
    const analysis = data?.quick_fixes ? data : typeof data === 'string' ? JSON.parse(data) : data
    if (!analysis?.department_reason && !analysis?.quick_fixes) {
      throw new Error('Asistan beklenmeyen bir yanıt döndü.')
    }
    messages.value.push({
      role: 'model',
      text: analysis?.department_reason || 'Analiz tamamlandı.',
      analysis,
    })
  } catch (e: any) {
    // Kullanıcı mesajı listede kaldıysa başarısız turu geri almayız; hata altta görünür.
    error.value = e?.message || 'Asistan yanıt veremedi.'
  } finally {
    loading.value = false
  }
}

function goCreate(analysis: any) {
  closeChat()
  navigateTo({
    path: '/requests/create',
    query: {
      description: messages.value.find((m) => m.role === 'user')?.text || '',
      departmentName: analysis?.department_name || '',
    },
  })
}
</script>

<template>
  <div class="pointer-events-none fixed bottom-5 right-5 z-50 flex flex-col items-end gap-3">
    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="translate-y-4 scale-95 opacity-0"
      enter-to-class="translate-y-0 scale-100 opacity-100"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="translate-y-0 scale-100 opacity-100"
      leave-to-class="translate-y-3 scale-95 opacity-0"
    >
      <div
        v-if="chatOpen"
        class="pointer-events-auto flex h-[min(580px,72vh)] w-[min(400px,calc(100vw-1.5rem))] flex-col overflow-hidden rounded-3xl border border-orange-200/40 bg-white shadow-[0_12px_40px_rgba(234,88,12,0.22),0_4px_12px_rgba(15,23,42,0.12)] dark:border-orange-900/40 dark:bg-gray-900 dark:shadow-[0_12px_40px_rgba(0,0,0,0.55)]"
      >
        <!-- Header -->
        <div class="relative overflow-hidden bg-gradient-to-br from-orange-500 via-orange-600 to-amber-600 px-4 pb-4 pt-3 text-white">
          <div class="pointer-events-none absolute -right-6 -top-8 h-28 w-28 rounded-full bg-white/10" />
          <div class="pointer-events-none absolute -bottom-10 left-10 h-24 w-24 rounded-full bg-black/10" />
          <div class="relative flex items-start justify-between gap-3">
            <div class="flex items-center gap-3">
              <div class="flex h-11 w-11 items-center justify-center rounded-2xl bg-white/20 shadow-inner ring-1 ring-white/30 backdrop-blur-sm">
                <svg class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                  <rect x="4" y="8" width="16" height="10" rx="2.5" />
                  <path d="M9 8V6.5a3 3 0 0 1 6 0V8" />
                  <circle cx="9.5" cy="13" r="1" fill="currentColor" stroke="none" />
                  <circle cx="14.5" cy="13" r="1" fill="currentColor" stroke="none" />
                </svg>
              </div>
              <div>
                <p class="text-[15px] font-semibold tracking-tight">Arıza Asistanı</p>
                <p class="text-[11px] text-orange-100/90">Pratik çözüm · birim önerisi</p>
              </div>
            </div>
            <button
              type="button"
              class="rounded-xl bg-white/15 p-2 ring-1 ring-white/20 transition hover:bg-white/25"
              @click="closeChat"
            >
              <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
                <path d="M18 6 6 18M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>

        <!-- Messages -->
        <div
          ref="listEl"
          class="flex-1 space-y-3 overflow-y-auto bg-[radial-gradient(ellipse_at_top,_rgba(251,146,60,0.08),_transparent_55%)] px-3 py-4 dark:bg-[radial-gradient(ellipse_at_top,_rgba(251,146,60,0.07),_transparent_50%)]"
        >
          <div
            v-if="!messages.length"
            class="mx-auto mt-6 max-w-[85%] rounded-2xl border border-dashed border-orange-300/50 bg-orange-50/80 px-4 py-5 text-center dark:border-orange-800/50 dark:bg-orange-950/30"
          >
            <p class="text-[13px] font-medium text-orange-800 dark:text-orange-200">Nasıl yardımcı olabilirim?</p>
            <p class="mt-1 text-[11px] leading-4 text-orange-700/80 dark:text-orange-300/70">
              Arızanızı yazın. Genel sohbet botu değil — yapılandırılmış çözüm önerir.
            </p>
          </div>

          <div
            v-for="(m, i) in messages"
            :key="i"
            class="flex"
            :class="m.role === 'user' ? 'justify-end' : 'justify-start'"
          >
            <div
              class="max-w-[88%] px-3.5 py-2.5 text-[13px] leading-5 shadow-sm"
              :class="m.role === 'user'
                ? 'rounded-2xl rounded-br-md bg-gradient-to-br from-orange-500 to-orange-600 text-white shadow-[0_4px_14px_rgba(234,88,12,0.35)]'
                : 'rounded-2xl rounded-bl-md border border-gray-200/80 bg-white text-gray-800 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100'"
            >
              <p class="whitespace-pre-wrap">{{ m.text }}</p>

              <div
                v-if="m.analysis?.quick_fixes?.length"
                class="mt-3 space-y-1.5 rounded-xl bg-orange-50/90 p-2.5 dark:bg-orange-950/40"
              >
                <p class="text-[10px] font-semibold uppercase tracking-wide text-orange-600 dark:text-orange-300">
                  Deneyebileceğiniz çözümler
                </p>
                <div
                  v-for="(fix, fi) in m.analysis.quick_fixes"
                  :key="fi"
                  class="flex gap-2 rounded-lg bg-white/80 px-2 py-1.5 text-[12px] text-gray-700 dark:bg-gray-900/50 dark:text-gray-200"
                >
                  <span class="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-orange-500 text-[10px] font-bold text-white">
                    {{ fi + 1 }}
                  </span>
                  <span>{{ fix }}</span>
                </div>
              </div>

              <div
                v-if="m.analysis?.department_name"
                class="mt-3 rounded-xl border border-orange-200/70 bg-gradient-to-r from-orange-50 to-amber-50 p-2.5 dark:border-orange-800/50 dark:from-orange-950/40 dark:to-amber-950/30"
              >
                <p class="text-[10px] font-semibold uppercase tracking-wide text-orange-600 dark:text-orange-300">
                  Önerilen birim
                </p>
                <p class="mt-0.5 text-[13px] font-semibold text-orange-800 dark:text-orange-200">
                  {{ m.analysis.department_name }}
                </p>
                <button
                  type="button"
                  class="mt-2 inline-flex items-center gap-1 rounded-xl bg-gradient-to-b from-orange-500 to-orange-600 px-3 py-1.5 text-[11px] font-medium text-white shadow-md shadow-orange-500/30 hover:from-orange-400 hover:to-orange-500"
                  @click="goCreate(m.analysis)"
                >
                  Talep oluştur
                  <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M5 12h14M13 5l7 7-7 7" />
                  </svg>
                </button>
              </div>
            </div>
          </div>

          <div v-if="loading" class="flex justify-start">
            <div class="flex items-center gap-1.5 rounded-2xl rounded-bl-md border border-gray-200 bg-white px-3.5 py-2.5 dark:border-gray-700 dark:bg-gray-800">
              <span class="h-2 w-2 animate-bounce rounded-full bg-orange-400 [animation-delay:-0.2s]" />
              <span class="h-2 w-2 animate-bounce rounded-full bg-orange-400 [animation-delay:-0.1s]" />
              <span class="h-2 w-2 animate-bounce rounded-full bg-orange-500" />
            </div>
          </div>
        </div>

        <p v-if="error" class="bg-red-50 px-4 py-2 text-[11px] text-red-600 dark:bg-red-950/40 dark:text-red-300">
          {{ error }}
        </p>

        <!-- Composer -->
        <form
          class="flex items-end gap-2 border-t border-gray-200/80 bg-white/90 p-3 backdrop-blur dark:border-gray-700 dark:bg-gray-900/90"
          @submit.prevent="send"
        >
          <input
            v-model="input"
            class="min-h-[42px] flex-1 rounded-2xl border-orange-200/60 bg-orange-50/40 text-[13px] dark:border-gray-700 dark:bg-gray-800"
            placeholder="Arızayı yazın…"
            :disabled="loading"
          />
          <button
            class="flex h-[42px] w-[42px] shrink-0 items-center justify-center rounded-2xl bg-gradient-to-b from-orange-500 to-orange-600 text-white shadow-md shadow-orange-500/35 transition hover:from-orange-400 hover:to-orange-500 disabled:opacity-50"
            type="submit"
            :disabled="loading || !input.trim()"
            title="Gönder"
          >
            <svg v-if="!loading" class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
              <path d="M3.4 20.6 21 12 3.4 3.4 3 10l11 2L3 14l.4 6.6Z" />
            </svg>
            <span v-else class="text-xs">…</span>
          </button>
        </form>
      </div>
    </Transition>

    <!-- Staff: messages FAB + orange AI badge | Citizen: orange AI only -->
    <div v-if="canViewIncoming" class="pointer-events-auto relative h-[72px] w-[72px]">
      <button
        type="button"
        class="absolute bottom-0 right-0 flex h-14 w-14 items-center justify-center rounded-full bg-gradient-to-b from-blue-500 to-blue-600 text-white shadow-[0_8px_20px_rgba(37,99,235,0.45)] transition hover:from-blue-400 hover:to-blue-500"
        title="Mesajlar"
        @click="openDmPanel()"
      >
        <svg class="h-6 w-6" viewBox="0 0 24 24" fill="currentColor">
          <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z" />
        </svg>
        <span
          v-if="dmUnread > 0"
          class="absolute -left-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold leading-none text-white ring-2 ring-white dark:ring-gray-900"
        >
          {{ dmUnread > 99 ? '99+' : dmUnread }}
        </span>
      </button>
      <button
        type="button"
        class="absolute -right-1.5 -top-1.5 flex h-9 w-9 items-center justify-center rounded-full border-2 border-white bg-gradient-to-b from-orange-500 to-orange-600 text-white shadow-[0_4px_12px_rgba(234,88,12,0.5)] hover:from-orange-400 dark:border-gray-900"
        title="Arıza Asistanı"
        @click="toggleChat"
      >
        <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <rect x="4" y="8" width="16" height="10" rx="2" />
          <path d="M9 8V6a3 3 0 0 1 6 0v2M9 14h.01M15 14h.01" />
        </svg>
      </button>
    </div>
    <button
      v-else
      type="button"
      class="pointer-events-auto flex h-12 w-12 items-center justify-center rounded-full bg-gradient-to-b from-orange-500 to-orange-600 text-white shadow-[0_8px_20px_rgba(234,88,12,0.45)] hover:from-orange-400"
      title="Arıza Asistanı"
      @click="toggleChat"
    >
      <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <rect x="4" y="8" width="16" height="10" rx="2" />
        <path d="M9 8V6a3 3 0 0 1 6 0v2M9 14h.01M15 14h.01" />
      </svg>
    </button>
  </div>
</template>
