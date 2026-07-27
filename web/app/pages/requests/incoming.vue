<script setup lang="ts">
import {
  applyRequestListFilters,
  requestSortOptions,
  requestTimeRangeOptions,
  type RequestSort,
  type RequestTimeRange,
} from '~/utils/requestListFilters'

const { user, role, canViewIncoming, isAdmin, isMudur } = useAuth()
const supabase = useSupabase()
const route = useRoute()

if (!canViewIncoming.value) {
  await navigateTo('/home')
}

const rows = ref<any[]>([])
const loading = ref(false)
const search = ref((route.query.q as string) || '')
const status = ref('')
const sort = ref<RequestSort>('newest')
const timeRange = ref<RequestTimeRange>('')
const page = ref(1)
const pageSize = 10

const pageCount = computed(() => Math.max(1, Math.ceil(rows.value.length / pageSize)))
const paged = computed(() => {
  const start = (page.value - 1) * pageSize
  return rows.value.slice(start, start + pageSize)
})

async function load() {
  if (!user.value) return
  loading.value = true
  try {
    let q = supabase
      .from('requests')
      .select('id, title, status, category, created_at, assigned_to, department_id, departments(name)')

    q = applyRequestListFilters(q, { sort: sort.value, timeRange: timeRange.value })

    if (role.value === 'personel') q = q.eq('assigned_to', user.value.id)
    else if (isMudur.value) q = q.eq('department_id', user.value.department_id)

    if (status.value) q = q.eq('status', status.value)
    if (search.value.trim()) {
      const v = escapeFilterValue(search.value.trim())
      q = q.or(`title.ilike."%${v}%",description.ilike."%${v}%"`)
    }

    const { data, error } = await q
    if (error) throw error
    rows.value = data || []
    page.value = 1
  } finally {
    loading.value = false
  }
}

onMounted(load)
watch([status, sort, timeRange], load)
</script>

<template>
  <div>
    <PageHeader title="Gelen Talepler" :subtitle="isAdmin ? 'Tüm sistem' : 'Biriminize / size atanan'" />
    <div class="card mb-4 flex flex-wrap gap-3 p-4 shadow-sm">
      <input v-model="search" class="min-w-[160px] flex-1" placeholder="Ara…" @keyup.enter="load" />
      <select v-model="status" class="min-w-[140px]">
        <option value="">Tüm durumlar</option>
        <option v-for="(label, key) in statusLabels" :key="key" :value="key">{{ label }}</option>
      </select>
      <select v-model="sort" class="min-w-[150px]" title="Sıralama">
        <option v-for="o in requestSortOptions" :key="o.value" :value="o.value">{{ o.label }}</option>
      </select>
      <select v-model="timeRange" class="min-w-[140px]" title="Zaman">
        <option v-for="o in requestTimeRangeOptions" :key="o.value || 'all'" :value="o.value">{{ o.label }}</option>
      </select>
      <button class="btn-secondary" type="button" @click="load">Filtrele</button>
    </div>

    <p v-if="loading" class="text-sm text-gray-500">Yükleniyor…</p>
    <div v-else class="card overflow-hidden shadow-sm">
      <div class="overflow-x-auto">
        <table class="w-full min-w-[640px] text-left text-sm">
          <thead>
            <tr class="border-b border-gray-200 text-xs uppercase text-gray-500 dark:border-gray-700">
              <th class="px-4 py-3 font-medium">Başlık</th>
              <th class="px-4 py-3 font-medium">Birim</th>
              <th class="px-4 py-3 font-medium">Durum</th>
              <th class="px-4 py-3 font-medium">Tarih</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="r in paged"
              :key="r.id"
              class="cursor-pointer border-b border-gray-200 last:border-0 hover:bg-gray-100/60 dark:border-gray-700 dark:hover:bg-gray-700/40"
              @click="navigateTo(`/requests/${r.id}`)"
            >
              <td class="px-4 py-3 font-medium text-gray-900 dark:text-gray-100">{{ r.title }}</td>
              <td class="px-4 py-3 text-gray-600 dark:text-gray-300">{{ r.departments?.name || '—' }}</td>
              <td class="px-4 py-3"><StatusBadge :status="r.status" /></td>
              <td class="px-4 py-3 text-gray-500">{{ new Date(r.created_at).toLocaleString('tr-TR') }}</td>
            </tr>
            <tr v-if="!paged.length">
              <td colspan="4" class="px-4 py-8 text-center text-gray-500">Kayıt yok.</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="border-t border-gray-200 px-4 py-3 dark:border-gray-700">
        <p class="mb-2 text-center text-xs text-gray-500">
          Toplam {{ rows.length }} kayıt · Sayfa {{ page }} / {{ pageCount }}
        </p>
        <PaginationBar v-model:page="page" :page-count="pageCount" />
      </div>
    </div>
  </div>
</template>
