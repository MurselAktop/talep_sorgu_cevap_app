<script setup lang="ts">
definePageMeta({ layout: 'auth' })

const supabase = useSupabase()
const title = ref('')
const description = ref('')
const category = ref('')
const departmentId = ref<number | null>(null)
const departments = ref<any[]>([])
const loading = ref(false)
const error = ref('')
const accessToken = ref('')

onMounted(async () => {
  const { data } = await supabase.from('departments').select('id, name').eq('is_active', true).order('name')
  departments.value = data || []
})

async function submit() {
  error.value = ''
  loading.value = true
  try {
    const { data, error: err } = await supabase.rpc('create_request', {
      p_title: title.value.trim(),
      p_description: description.value.trim(),
      p_category: category.value.trim(),
      p_department_id: departmentId.value,
      p_requester_type: 'anonim',
      p_created_by: null,
    })
    if (err) throw err
    const result = typeof data === 'string' ? JSON.parse(data) : data
    accessToken.value = result.access_token || result
  } catch (e: any) {
    error.value = e?.message || 'Talep oluşturulamadı.'
  } finally {
    loading.value = false
  }
}

async function copyToken() {
  try {
    await navigator.clipboard.writeText(accessToken.value)
  } catch {
    /* ignore */
  }
}
</script>

<template>
  <div class="card space-y-6 p-8 sm:p-9">
    <div class="flex items-center justify-between gap-3">
      <NuxtLink
        to="/guest"
        class="text-sm text-gray-500 transition hover:text-gray-800 dark:text-gray-400 dark:hover:text-white"
      >
        ← Geri
      </NuxtLink>
      <span class="rounded-full bg-amber-500/10 px-3 py-1 text-xs font-medium text-amber-700 dark:text-amber-300">
        Anonim
      </span>
    </div>

    <div>
      <h1 class="text-xl font-semibold tracking-tight text-gray-900 dark:text-white">Anonim Talep</h1>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        Giriş gerekmez. Oluşan erişim kodunu saklayın.
      </p>
    </div>

    <div v-if="accessToken" class="space-y-4 text-center">
      <div
        class="rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm font-medium text-emerald-800 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-300"
      >
        Talep oluşturuldu
      </div>
      <p class="text-sm text-gray-500 dark:text-gray-400">Erişim kodunuz (saklayın):</p>
      <p
        class="rounded-2xl border border-gray-200 bg-slate-50 py-4 font-mono text-lg tracking-[0.2em] text-gray-900 dark:border-gray-600 dark:bg-gray-900/60 dark:text-white"
      >
        {{ accessToken }}
      </p>
      <button class="btn-secondary w-full" type="button" @click="copyToken">Kodu Kopyala</button>
      <NuxtLink to="/guest/query" class="btn-primary w-full py-3">Sonucu Sorgula</NuxtLink>
    </div>

    <form v-else class="space-y-4" @submit.prevent="submit">
      <div>
        <label>Başlık</label>
        <input v-model="title" required placeholder="Kısa özet" />
      </div>
      <div>
        <label>Açıklama</label>
        <textarea v-model="description" required rows="4" placeholder="Sorunu detaylı yazın" />
      </div>
      <div>
        <label>Kategori</label>
        <input v-model="category" required placeholder="Örn. İnternet, Elektrik" />
      </div>
      <div>
        <label>Birim</label>
        <select v-model="departmentId" required>
          <option :value="null" disabled>Seçin</option>
          <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
        </select>
      </div>

      <p
        v-if="error"
        class="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-300"
      >
        {{ error }}
      </p>

      <button class="btn-primary w-full py-3" type="submit" :disabled="loading">
        {{ loading ? 'Gönderiliyor…' : 'Gönder' }}
      </button>
    </form>
  </div>
</template>
