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
  <div class="card space-y-4">
    <h1 class="text-xl font-semibold text-center">Sonuç Sorgula</h1>
    <form class="space-y-3" @submit.prevent="query">
      <div>
        <label>Erişim kodu</label>
        <input v-model="token" required class="w-full font-mono" />
      </div>
      <p v-if="error" class="text-sm text-status-reddedildi">{{ error }}</p>
      <button class="btn-primary w-full" type="submit" :disabled="loading">
        {{ loading ? 'Sorgulanıyor…' : 'Sorgula' }}
      </button>
    </form>
    <div v-if="result" class="rounded-lg bg-gray-100 dark:bg-gray-900 p-4 space-y-2 text-sm">
      <p><span class="text-white/50">Başlık:</span> {{ result.title }}</p>
      <p><span class="text-white/50">Birim:</span> {{ result.department_name || '—' }}</p>
      <p class="flex items-center gap-2">
        <span class="text-white/50">Durum:</span>
        <StatusBadge :status="result.status" />
      </p>
      <p><span class="text-white/50">Tarih:</span> {{ result.created_at ? new Date(result.created_at).toLocaleString('tr-TR') : '—' }}</p>
    </div>
    <NuxtLink to="/guest" class="block text-center text-sm text-white/60">Geri</NuxtLink>
  </div>
</template>
