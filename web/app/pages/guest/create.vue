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
</script>

<template>
  <div class="card space-y-4">
    <h1 class="text-xl font-semibold text-center">Anonim Talep</h1>
    <div v-if="accessToken" class="space-y-3 text-center">
      <p class="text-status-onaylandi">Talep oluşturuldu.</p>
      <p class="text-sm text-white/60">Erişim kodunuz (saklayın):</p>
      <p class="font-mono text-lg tracking-wider bg-gray-100 dark:bg-gray-900 rounded-lg py-3">{{ accessToken }}</p>
      <NuxtLink to="/guest/query" class="btn-primary w-full">Sonucu Sorgula</NuxtLink>
    </div>
    <form v-else class="space-y-3" @submit.prevent="submit">
      <div>
        <label>Başlık</label>
        <input v-model="title" required class="w-full" />
      </div>
      <div>
        <label>Açıklama</label>
        <textarea v-model="description" required rows="4" class="w-full" />
      </div>
      <div>
        <label>Kategori</label>
        <input v-model="category" required class="w-full" />
      </div>
      <div>
        <label>Birim</label>
        <select v-model="departmentId" required class="w-full">
          <option :value="null" disabled>Seçin</option>
          <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
        </select>
      </div>
      <p v-if="error" class="text-sm text-status-reddedildi">{{ error }}</p>
      <button class="btn-primary w-full" type="submit" :disabled="loading">
        {{ loading ? 'Gönderiliyor…' : 'Gönder' }}
      </button>
      <NuxtLink to="/guest" class="block text-center text-sm text-white/60">Geri</NuxtLink>
    </form>
  </div>
</template>
