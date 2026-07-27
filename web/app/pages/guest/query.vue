<script setup lang="ts">
definePageMeta({ layout: 'auth' })

const supabase = useSupabase()
const token = ref('')
const loading = ref(false)
const error = ref('')
const result = ref<any>(null)

async function query() {
  error.value = ''
  result.value = null
  loading.value = true
  try {
    const { data, error: err } = await supabase.rpc('get_request_by_token', {
      p_access_token: token.value.trim(),
    })
    if (err) throw err
    const row = Array.isArray(data) ? data[0] : data
    if (!row) {
      error.value = 'Kayıt bulunamadı.'
      return
    }
    result.value = row
  } catch (e: any) {
    error.value = e?.message || 'Sorgulama başarısız.'
  } finally {
    loading.value = false
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
      <span class="rounded-full bg-sky-500/10 px-3 py-1 text-xs font-medium text-sky-700 dark:text-sky-300">
        Sorgu
      </span>
    </div>

    <div>
      <h1 class="text-xl font-semibold tracking-tight text-gray-900 dark:text-white">Sonuç Sorgula</h1>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        Talebinize verilen erişim kodunu girin
      </p>
    </div>

    <form class="space-y-4" @submit.prevent="query">
      <div>
        <label>Erişim kodu</label>
        <input
          v-model="token"
          required
          class="font-mono tracking-wider"
          placeholder="Örn. AB12CD34"
          autocomplete="off"
        />
      </div>

      <p
        v-if="error"
        class="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-300"
      >
        {{ error }}
      </p>

      <button class="btn-primary w-full py-3" type="submit" :disabled="loading">
        {{ loading ? 'Sorgulanıyor…' : 'Sorgula' }}
      </button>
    </form>

    <div
      v-if="result"
      class="space-y-3 rounded-2xl border border-gray-200 bg-slate-50 p-4 text-sm dark:border-gray-600 dark:bg-gray-900/50"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <p class="text-xs text-gray-500 dark:text-gray-400">Başlık</p>
          <p class="font-medium text-gray-900 dark:text-white">{{ result.title }}</p>
        </div>
        <StatusBadge :status="result.status" />
      </div>
      <div>
        <p class="text-xs text-gray-500 dark:text-gray-400">Birim</p>
        <p class="text-gray-800 dark:text-gray-200">{{ result.department_name || '—' }}</p>
      </div>
      <div>
        <p class="text-xs text-gray-500 dark:text-gray-400">Tarih</p>
        <p class="text-gray-800 dark:text-gray-200">
          {{ result.created_at ? new Date(result.created_at).toLocaleString('tr-TR') : '—' }}
        </p>
      </div>
    </div>
  </div>
</template>
