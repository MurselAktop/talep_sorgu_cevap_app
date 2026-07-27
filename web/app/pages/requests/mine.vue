<script setup lang="ts">
import {
  applyRequestListFilters,
  requestSortOptions,
  requestTimeRangeOptions,
  type RequestSort,
  type RequestTimeRange,
} from '~/utils/requestListFilters'

const { user } = useAuth()
const supabase = useSupabase()

const rows = ref<any[]>([])
const loading = ref(false)
const search = ref('')
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
      .select('id, title, status, category, created_at, departments(name)')
      .eq('created_by', user.value.id)

    q = applyRequestListFilters(q, { sort: sort.value, timeRange: timeRange.value })

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
    <PageHeader title="Taleplerim" subtitle="Sizin oluşturduğunuz talepler" />
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
      <div class="divide-y divide-gray-200 dark:divide-gray-700">
        <NuxtLink
          v-for="r in paged"
          :key="r.id"
          :to="`/requests/${r.id}`"
          class="block px-4 py-3 transition hover:bg-gray-100/60 dark:hover:bg-gray-700/40"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="font-medium text-gray-900 dark:text-gray-100">{{ r.title }}</p>
              <p class="mt-1 text-xs text-gray-500">
                {{ r.departments?.name || '—' }} · {{ new Date(r.created_at).toLocaleString('tr-TR') }}
              </p>
            </div>
            <StatusBadge :status="r.status" />
          </div>
        </NuxtLink>
        <p v-if="!paged.length" class="px-4 py-8 text-center text-sm text-gray-500">Kayıt yok.</p>
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
