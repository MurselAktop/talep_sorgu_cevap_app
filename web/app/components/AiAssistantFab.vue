<script setup lang="ts">
const supabase = useSupabase()
const open = ref(false)
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
    const bodyError =
      data && typeof data === 'object' && typeof (data as any).error === 'string'
        ? (data as any).error as string
        : null
    if (err || bodyError) throw new Error(bodyError || err?.message || 'Asistan yanıt veremedi.')
    const analysis = data?.quick_fixes ? data : typeof data === 'string' ? JSON.parse(data) : data
    messages.value.push({
      role: 'model',
      text: analysis?.department_reason || 'Analiz tamamlandı.',
      analysis,
    })
  } catch (e: any) {
    error.value = e?.message || 'Asistan yanıt veremedi.'
  } finally {
    loading.value = false
  }
}

function goCreate(analysis: any) {
  open.value = false
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
    <!-- Chat panel -->
    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="translate-y-3 opacity-0"
      enter-to-class="translate-y-0 opacity-100"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="translate-y-0 opacity-100"
      leave-to-class="translate-y-3 opacity-0"
    >
      <div
        v-if="open"
        class="pointer-events-auto flex h-[min(560px,70vh)] w-[min(380px,calc(100vw-2rem))] flex-col overflow-hidden rounded-2xl border border-gray-200 bg-slate-50 shadow-xl dark:border-gray-700 dark:bg-gray-800"
      >
        <div class="flex items-center justify-between bg-blue-600 px-4 py-3 text-white">
          <div>
            <p class="text-sm font-semibold">Arıza Asistanı</p>
            <p class="text-xs text-blue-100">Yapılandırılmış çözüm önerileri</p>
          </div>
          <button type="button" class="rounded-lg p-1 hover:bg-blue-500" @click="open = false">
            <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M18 6 6 18M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div ref="listEl" class="flex-1 space-y-2 overflow-y-auto p-3">
          <p v-if="!messages.length" class="text-xs text-gray-500 dark:text-gray-400">
            Sorununuzu yazın. Asistan genel sohbet botu değildir.
          </p>
          <div
            v-for="(m, i) in messages"
            :key="i"
            class="max-w-[90%] rounded-xl px-3 py-2 text-sm"
            :class="m.role === 'user'
              ? 'ml-auto bg-blue-600 text-white'
              : 'bg-white text-gray-800 dark:bg-gray-900 dark:text-gray-100'"
          >
            <p class="whitespace-pre-wrap">{{ m.text }}</p>
            <ol v-if="m.analysis?.quick_fixes?.length" class="mt-2 list-decimal space-y-1 pl-4 text-xs">
              <li v-for="(fix, fi) in m.analysis.quick_fixes" :key="fi">{{ fix }}</li>
            </ol>
            <p v-if="m.analysis?.department_name" class="mt-2 text-xs font-medium text-blue-600 dark:text-blue-400">
              Birim: {{ m.analysis.department_name }}
            </p>
            <button
              v-if="m.analysis?.department_name"
              type="button"
              class="mt-2 rounded-lg bg-blue-600 px-2 py-1 text-xs text-white hover:bg-blue-500"
              @click="goCreate(m.analysis)"
            >
              Talep oluştur
            </button>
          </div>
        </div>

        <p v-if="error" class="px-3 text-xs text-red-500">{{ error }}</p>
        <form class="flex gap-2 border-t border-gray-200 p-3 dark:border-gray-700" @submit.prevent="send">
          <input
            v-model="input"
            class="flex-1 rounded-xl border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-900"
            placeholder="Arızayı yazın…"
            :disabled="loading"
          />
          <button class="btn-primary px-3" type="submit" :disabled="loading">
            {{ loading ? '…' : '→' }}
          </button>
        </form>
      </div>
    </Transition>

    <!-- FAB -->
    <button
      type="button"
      class="pointer-events-auto flex h-14 w-14 items-center justify-center rounded-full bg-blue-600 text-white shadow-lg transition-colors duration-150 hover:bg-blue-500"
      aria-label="Arıza Asistanı"
      @click="open = !open"
    >
      <svg v-if="!open" class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M21 15a4 4 0 0 1-4 4H8l-5 3V7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4z" />
      </svg>
      <svg v-else class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M18 6 6 18M6 6l12 12" />
      </svg>
    </button>
  </div>
</template>
