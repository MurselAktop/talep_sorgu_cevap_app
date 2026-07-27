<script setup lang="ts">
const { isAdmin, user } = useAuth()
const supabase = useSupabase()
const route = useRoute()
if (!isAdmin.value) await navigateTo('/home')

type MainTab = 'vatandas' | 'personel' | 'birimler'
type StaffTab = 'personel' | 'mudur' | 'admin'

const mainTab = ref<MainTab>(
  (['vatandas', 'personel', 'birimler'].includes(String(route.query.tab))
    ? String(route.query.tab)
    : 'vatandas') as MainTab,
)
const staffTab = ref<StaffTab>(
  (['personel', 'mudur', 'admin'].includes(String(route.query.role))
    ? String(route.query.role)
    : 'personel') as StaffTab,
)

const users = ref<any[]>([])
const departments = ref<any[]>([])
const message = ref('')
const messageTone = ref<'ok' | 'err'>('ok')
const page = ref(1)
const pageSize = 8

const newDeptName = ref('')
const editId = ref<number | null>(null)
const editName = ref('')

function flash(text: string, tone: 'ok' | 'err' = 'ok') {
  message.value = text
  messageTone.value = tone
}

const filteredUsers = computed(() => {
  if (mainTab.value === 'vatandas') {
    return users.value.filter((u) => u.role === 'vatandas')
  }
  if (mainTab.value === 'personel') {
    return users.value.filter((u) => u.role === staffTab.value)
  }
  return []
})

const pageCount = computed(() => Math.max(1, Math.ceil(filteredUsers.value.length / pageSize)))
const paged = computed(() => {
  const start = (page.value - 1) * pageSize
  return filteredUsers.value.slice(start, start + pageSize)
})

watch([mainTab, staffTab], () => {
  page.value = 1
  navigateTo({
    path: '/admin/users',
    query: {
      tab: mainTab.value,
      ...(mainTab.value === 'personel' ? { role: staffTab.value } : {}),
    },
    replace: true,
  })
})

async function loadUsers() {
  const { data } = await supabase
    .from('users')
    .select('id, full_name, email, role, is_active, departments(name)')
    .order('full_name')
  users.value = data || []
}

async function loadDepartments() {
  const { data } = await supabase.from('departments').select('*').order('name')
  departments.value = data || []
}

async function toggle(row: any) {
  if (row.id === user.value?.id) {
    flash('Kendi hesabınızı pasifleştiremezsiniz.', 'err')
    return
  }
  const { error } = await supabase.rpc('admin_set_user_active', {
    p_user_id: row.id,
    p_is_active: !row.is_active,
  })
  flash(error ? error.message : 'Güncellendi.', error ? 'err' : 'ok')
  await loadUsers()
}

async function addDepartment() {
  const { error } = await supabase
    .from('departments')
    .insert({ name: newDeptName.value.trim(), is_active: true })
  flash(error ? error.message : 'Birim eklendi.', error ? 'err' : 'ok')
  newDeptName.value = ''
  await loadDepartments()
}

async function saveDepartmentEdit() {
  if (editId.value == null) return
  const { error } = await supabase
    .from('departments')
    .update({ name: editName.value.trim() })
    .eq('id', editId.value)
  flash(error ? error.message : 'Birim güncellendi.', error ? 'err' : 'ok')
  editId.value = null
  await loadDepartments()
}

async function setDepartmentActive(id: number, active: boolean) {
  const { error } = await supabase.from('departments').update({ is_active: active }).eq('id', id)
  flash(error ? error.message : active ? 'Aktifleştirildi.' : 'Pasifleştirildi.', error ? 'err' : 'ok')
  await loadDepartments()
}

onMounted(async () => {
  await Promise.all([loadUsers(), loadDepartments()])
})
</script>

<template>
  <div>
    <PageHeader
      title="Vatandaş / Personel"
      subtitle="Kullanıcıları rollere göre yönetin · birimleri buradan düzenleyin"
    />

    <p
      v-if="message"
      class="mb-3 rounded-xl px-4 py-2.5 text-[13px]"
      :class="messageTone === 'ok'
        ? 'border border-teal-500/30 bg-teal-500/10 text-teal-700 dark:text-teal-300'
        : 'border border-red-500/30 bg-red-500/10 text-red-700 dark:text-red-300'"
    >
      {{ message }}
    </p>

    <!-- Ana sekmeler -->
    <div class="mb-4 flex flex-wrap gap-1 rounded-2xl border border-gray-200/80 bg-white/70 p-1 dark:border-gray-700 dark:bg-gray-800/70">
      <button
        v-for="t in [
          { id: 'vatandas', label: 'Vatandaş' },
          { id: 'personel', label: 'Personel' },
          { id: 'birimler', label: 'Birimler' },
        ]"
        :key="t.id"
        type="button"
        class="rounded-xl px-4 py-2 text-[13px] font-medium transition"
        :class="mainTab === t.id
          ? 'bg-blue-600 text-white shadow-md'
          : 'text-gray-600 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700'"
        @click="mainTab = t.id as MainTab"
      >
        {{ t.label }}
      </button>
    </div>

    <!-- Personel alt sekmeleri -->
    <div
      v-if="mainTab === 'personel'"
      class="mb-4 flex flex-wrap gap-1 rounded-xl border border-gray-200/60 bg-slate-50 p-1 dark:border-gray-700 dark:bg-gray-900/50"
    >
      <button
        v-for="t in [
          { id: 'personel', label: 'Personel' },
          { id: 'mudur', label: 'Müdür' },
          { id: 'admin', label: 'Admin' },
        ]"
        :key="t.id"
        type="button"
        class="rounded-lg px-3 py-1.5 text-[12px] font-medium transition"
        :class="staffTab === t.id
          ? 'bg-white text-blue-600 shadow-sm dark:bg-gray-800 dark:text-blue-300'
          : 'text-gray-500 hover:text-gray-800 dark:hover:text-gray-200'"
        @click="staffTab = t.id as StaffTab"
      >
        {{ t.label }}
      </button>
    </div>

    <!-- Kullanıcı listesi -->
    <div v-if="mainTab !== 'birimler'" class="card overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full min-w-[640px] text-left text-[13px]">
          <thead>
            <tr class="border-b border-gray-200 text-[11px] uppercase tracking-wide text-gray-500 dark:border-gray-700">
              <th class="px-4 py-3 font-medium">Ad Soyad</th>
              <th class="px-4 py-3 font-medium">E-posta</th>
              <th class="px-4 py-3 font-medium">Rol</th>
              <th class="px-4 py-3 font-medium">Birim</th>
              <th class="px-4 py-3 font-medium">Durum</th>
              <th class="px-4 py-3 font-medium">İşlem</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="u in paged"
              :key="u.id"
              class="border-b border-gray-200 last:border-0 dark:border-gray-700"
            >
              <td class="px-4 py-3 font-medium text-gray-900 dark:text-gray-100">{{ u.full_name }}</td>
              <td class="px-4 py-3 text-gray-600 dark:text-gray-300">{{ u.email }}</td>
              <td class="px-4 py-3">{{ roleLabels[u.role] || u.role }}</td>
              <td class="px-4 py-3">{{ u.departments?.name || '—' }}</td>
              <td class="px-4 py-3">
                <span
                  class="rounded-full px-2 py-0.5 text-[11px] font-medium"
                  :class="u.is_active === false
                    ? 'bg-red-500/20 text-red-400'
                    : 'bg-teal-500/20 text-teal-400'"
                >
                  {{ u.is_active === false ? 'Pasif' : 'Aktif' }}
                </span>
              </td>
              <td class="px-4 py-3">
                <button
                  v-if="u.id !== user?.id"
                  class="btn-secondary px-3 py-1.5 text-xs"
                  type="button"
                  @click="toggle(u)"
                >
                  {{ u.is_active === false ? 'Aktifleştir' : 'Pasifleştir' }}
                </button>
              </td>
            </tr>
            <tr v-if="!paged.length">
              <td colspan="6" class="px-4 py-8 text-center text-gray-500">Bu sekmede kayıt yok.</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="border-t border-gray-200 px-4 py-3 dark:border-gray-700">
        <p class="mb-2 text-center text-[11px] text-gray-500">
          {{ filteredUsers.length }} kayıt · Sayfa {{ page }} / {{ pageCount }}
        </p>
        <PaginationBar v-model:page="page" :page-count="pageCount" />
      </div>
    </div>

    <!-- Birimler -->
    <div v-else class="space-y-4">
      <form class="card flex flex-wrap gap-2 p-4" @submit.prevent="addDepartment">
        <input v-model="newDeptName" class="min-w-[200px] flex-1" placeholder="Yeni birim adı" required />
        <button class="btn-primary" type="submit">Ekle</button>
      </form>

      <div class="grid gap-3 sm:grid-cols-2">
        <div
          v-for="d in departments"
          :key="d.id"
          class="card flex flex-wrap items-center justify-between gap-3 p-4"
        >
          <div>
            <p class="text-[13px] font-semibold text-gray-900 dark:text-white">{{ d.name }}</p>
            <p class="text-[11px] text-gray-500">{{ d.is_active ? 'Aktif' : 'Pasif' }}</p>
          </div>
          <div class="flex gap-2">
            <button
              class="btn-secondary px-3 py-1.5 text-xs"
              type="button"
              @click="editId = d.id; editName = d.name"
            >
              Düzenle
            </button>
            <button
              class="btn-secondary px-3 py-1.5 text-xs"
              type="button"
              @click="setDepartmentActive(d.id, !d.is_active)"
            >
              {{ d.is_active ? 'Pasifleştir' : 'Aktifleştir' }}
            </button>
          </div>
        </div>
      </div>
      <p v-if="!departments.length" class="text-sm text-gray-500">Henüz birim yok.</p>
    </div>

    <div
      v-if="editId != null"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      @click.self="editId = null"
    >
      <form class="card w-full max-w-md space-y-3 p-5" @submit.prevent="saveDepartmentEdit">
        <h3 class="text-[13px] font-semibold">Birim adı</h3>
        <input v-model="editName" class="w-full" required />
        <div class="flex gap-2">
          <button class="btn-primary" type="submit">Kaydet</button>
          <button class="btn-secondary" type="button" @click="editId = null">İptal</button>
        </div>
      </form>
    </div>
  </div>
</template>
