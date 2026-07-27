<script setup lang="ts">
const { isAdmin, user } = useAuth()
const supabase = useSupabase()
if (!isAdmin.value) await navigateTo('/home')

const departments = ref<any[]>([])
const invites = ref<any[]>([])
const departmentId = ref<number | null>(null)
const role = ref('personel')
const message = ref('')
const createdCode = ref('')

async function load() {
  const [{ data: deps }, { data: inv }] = await Promise.all([
    supabase.from('departments').select('id, name').eq('is_active', true).order('name'),
    supabase.from('personnel_invites').select('*, departments(name)').order('created_at', { ascending: false }),
  ])
  departments.value = deps || []
  invites.value = inv || []
}

async function create() {
  createdCode.value = ''
  const { data, error } = await supabase
    .from('personnel_invites')
    .insert({
      department_id: departmentId.value,
      role: role.value,
      created_by: user.value?.id,
    })
    .select('code')
    .single()
  message.value = error ? error.message : 'Davet oluşturuldu.'
  if (data?.code) createdCode.value = data.code
  await load()
}

onMounted(load)
</script>

<template>
  <div>
    <PageHeader title="Davet Kodu Oluştur" />
    <form class="card max-w-lg space-y-3 mb-4" @submit.prevent="create">
      <div>
        <label>Birim</label>
        <select v-model="departmentId" required class="w-full">
          <option :value="null" disabled>Seçin</option>
          <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
        </select>
      </div>
      <div>
        <label>Rol</label>
        <select v-model="role" class="w-full">
          <option value="personel">Personel</option>
          <option value="mudur">Müdür</option>
          <option value="admin">Admin</option>
        </select>
      </div>
      <button class="btn-primary" type="submit">Oluştur</button>
      <p v-if="createdCode" class="font-mono text-lg bg-gray-100 dark:bg-gray-900 rounded-lg p-3 text-center">
        {{ createdCode }}
      </p>
      <p v-if="message" class="text-sm text-blue-400">{{ message }}</p>
    </form>
    <div class="space-y-2">
      <div v-for="i in invites" :key="i.id" class="card text-sm">
        <p class="font-mono">{{ i.code }}</p>
        <p class="text-white/50 text-xs mt-1">
          {{ i.departments?.name }} · {{ roleLabels[i.role] || i.role }} ·
          {{ i.used ? 'Kullanıldı' : 'Bekliyor' }}
        </p>
      </div>
    </div>
  </div>
</template>
