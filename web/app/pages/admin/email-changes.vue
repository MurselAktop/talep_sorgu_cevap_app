<script setup lang="ts">
const { isAdmin } = useAuth()
const supabase = useSupabase()
if (!isAdmin.value) await navigateTo('/home')

const rows = ref<any[]>([])
const error = ref('')
const available = ref(true)

onMounted(async () => {
  const { data, error: err } = await supabase
    .from('email_change_requests')
    .select('*')
    .order('created_at', { ascending: false })
  if (err) {
    available.value = false
    error.value = err.message
    return
  }
  rows.value = data || []
})
</script>

<template>
  <div>
    <PageHeader title="E-posta Değişiklik Talepleri" />
    <div v-if="!available" class="card text-sm text-white/60">
      Bu tabloya erişilemedi veya henüz yok. Mobildeki ekranla aynı veri kaynağı bekleniyor.
      <p class="mt-2 text-xs">{{ error }}</p>
    </div>
    <div v-else class="space-y-2">
      <div v-for="r in rows" :key="r.id" class="card text-sm">
        <pre class="whitespace-pre-wrap text-xs text-white/70">{{ r }}</pre>
      </div>
      <p v-if="!rows.length" class="text-white/50 text-sm">Bekleyen talep yok.</p>
    </div>
  </div>
</template>
