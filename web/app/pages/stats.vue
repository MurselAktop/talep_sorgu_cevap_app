<script setup lang="ts">
const { isAdmin, isMudur } = useAuth()
const supabase = useSupabase()

if (!isAdmin.value && !isMudur.value) await navigateTo('/home')

const rows = ref<any[]>([])
const trendRows = ref<any[]>([])
const personnelRatings = ref<any[]>([])
const loading = ref(true)
const error = ref('')
const animReady = ref(false)

function countOf(row: any) {
  return Number(row.request_count ?? row.count ?? row.cnt ?? 0)
}

onMounted(async () => {
  try {
    const { data: sessionData } = await supabase.auth.getSession()
    const token = sessionData.session?.access_token || ''
    const pack = await fetchDashboardStats({
      isAdmin: isAdmin.value,
      accessToken: token,
    })
    rows.value = pack.rows
    trendRows.value = pack.trendRows
    personnelRatings.value = pack.personnelRatings
    if (pack.error) error.value = pack.error
  } catch (e: any) {
    error.value = e?.message || 'İstatistikler yüklenemedi.'
  } finally {
    loading.value = false
    await nextTick()
    animReady.value = true
  }
})

const statusOrder = ['acik', 'cozuldu', 'onaylandi', 'reddedildi', 'iptal'] as const

const statusTotals = computed(() => {
  const map: Record<string, number> = { acik: 0, cozuldu: 0, onaylandi: 0, reddedildi: 0, iptal: 0 }
  let total = 0
  for (const row of rows.value) {
    const s = String(row.status || '')
    const c = countOf(row)
    if (s in map) map[s] += c
    total += c
  }
  return { total, map }
})

const statusColorMap: Record<string, string> = {
  acik: '#F59E0B',
  cozuldu: '#3B82F6',
  onaylandi: '#14B8A6',
  reddedildi: '#EF4444',
  iptal: '#9CA3AF',
}

const pieKeys = computed(() =>
  statusOrder.filter((k) => (statusTotals.value.map[k] || 0) > 0),
)
const pieLabels = computed(() => pieKeys.value.map((k) => statusLabels[k] || k))
const pieValues = computed(() => pieKeys.value.map((k) => statusTotals.value.map[k] || 0))
const pieColors = computed(() => pieKeys.value.map((k) => statusColorMap[k] || '#9CA3AF'))

const barLabels = computed(() =>
  (['acik', 'cozuldu', 'onaylandi', 'reddedildi'] as const).map((k) => statusLabels[k] || k),
)
const barValues = computed(() =>
  (['acik', 'cozuldu', 'onaylandi', 'reddedildi'] as const).map((k) => statusTotals.value.map[k] || 0),
)
const barColors = computed(() =>
  (['acik', 'cozuldu', 'onaylandi', 'reddedildi'] as const).map((k) => statusColorMap[k]),
)

const byDepartment = computed(() => {
  const out: Record<string, Record<string, number>> = {}
  for (const row of rows.value) {
    const dept = String(row.department_name || row.department || '—')
    const status = String(row.status || '')
    out[dept] ??= {}
    out[dept][status] = (out[dept][status] || 0) + countOf(row)
  }
  return out
})

const departmentRatings = computed(() => {
  const weightedSum: Record<string, number> = {}
  const counts: Record<string, number> = {}
  for (const row of personnelRatings.value) {
    const dept = row.department_name as string | null
    const avg = Number(row.avg_rating ?? 0)
    const rc = Number(row.rating_count ?? 0)
    if (!dept || !rc) continue
    weightedSum[dept] = (weightedSum[dept] || 0) + avg * rc
    counts[dept] = (counts[dept] || 0) + rc
  }
  const out: Record<string, number> = {}
  for (const [k, c] of Object.entries(counts)) out[k] = weightedSum[k]! / c
  return out
})

const managerAvgRating = computed(() => {
  let weightedSum = 0
  let weightedCount = 0
  for (const row of personnelRatings.value) {
    const avg = Number(row.avg_rating ?? 0)
    const rc = Number(row.rating_count ?? 0)
    if (!rc) continue
    weightedSum += avg * rc
    weightedCount += rc
  }
  return weightedCount === 0 ? null : weightedSum / weightedCount
})
</script>

<template>
  <div>
    <PageHeader title="Detaylı Raporlar" :subtitle="isAdmin ? 'Sistem geneli istatistikler' : 'Biriminizin istatistikleri'" />
    <p v-if="loading" class="text-sm text-gray-500">Yükleniyor…</p>
    <p v-else-if="error" class="text-sm text-red-500">{{ error }}</p>
    <div v-else class="space-y-4">
      <!-- KPI -->
      <div class="grid grid-cols-2 gap-3 md:grid-cols-5">
        <div class="card p-4">
          <p class="text-xs text-gray-500">Toplam</p>
          <p class="text-3xl font-bold text-gray-900 dark:text-white">
            <AnimatedNumber v-if="animReady" :value="statusTotals.total" />
            <span v-else>0</span>
          </p>
        </div>
        <div v-for="key in ['acik', 'cozuldu', 'onaylandi', 'reddedildi']" :key="key" class="card p-4">
          <p class="text-xs text-gray-500">{{ statusLabels[key] }}</p>
          <p class="text-3xl font-bold text-gray-900 dark:text-white">
            <AnimatedNumber v-if="animReady" :value="statusTotals.map[key] || 0" />
            <span v-else>0</span>
          </p>
        </div>
      </div>

      <div v-if="!isAdmin && managerAvgRating != null" class="card flex items-center justify-between gap-3 p-4">
        <div>
          <p class="text-sm text-gray-500">Birimin Ortalama Değerlendirme Puanı</p>
          <p class="text-2xl font-semibold text-amber-500">★ {{ managerAvgRating.toFixed(1) }}</p>
        </div>
      </div>

      <!-- Durum grafikleri -->
      <div class="grid gap-4 lg:grid-cols-2">
        <div class="card p-4">
          <h2 class="mb-3 text-[13px] font-semibold text-gray-900 dark:text-white">Durum Dağılımı</h2>
          <StatusDonutChart
            v-if="animReady && pieValues.some((v) => v > 0)"
            :labels="pieLabels"
            :values="pieValues"
            :colors="pieColors"
          />
          <p v-else class="py-16 text-center text-sm text-gray-500">Veri yok.</p>
        </div>
        <div class="card p-4">
          <h2 class="mb-3 text-[13px] font-semibold text-gray-900 dark:text-white">Durumlara Göre Adet</h2>
          <StatusBarChart
            v-if="animReady"
            :labels="barLabels"
            :values="barValues"
            :colors="barColors"
          />
        </div>
      </div>

      <!-- Aylık çözüm süresi -->
      <div class="card p-4">
        <h2 class="mb-3 text-[13px] font-semibold text-gray-900 dark:text-white">
          Aylık Ortalama Çözüm Süresi
        </h2>
        <ResolutionTrendChart v-if="animReady" :rows="trendRows" />
      </div>

      <!-- Admin: birim grafikleri (mobildeki gibi) -->
      <div v-if="isAdmin" class="grid gap-4 lg:grid-cols-2">
        <div class="card p-4">
          <h2 class="mb-3 text-[13px] font-semibold text-gray-900 dark:text-white">Birim × Durum</h2>
          <DeptStatusBarChart v-if="animReady" :by-department="byDepartment" />
        </div>
        <div class="card p-4">
          <h2 class="mb-3 text-[13px] font-semibold text-gray-900 dark:text-white">
            Birim Bazlı Ortalama Puan
          </h2>
          <DeptRatingBarChart v-if="animReady" :ratings="departmentRatings" />
        </div>
      </div>

      <!-- Tablo özeti -->
      <div class="card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="text-left text-xs uppercase text-gray-500">
            <tr class="border-b border-gray-200 dark:border-gray-700">
              <th class="px-4 py-3">Durum</th>
              <th class="px-4 py-3">Adet</th>
              <th class="px-4 py-3">Oran</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="key in statusOrder"
              :key="key"
              class="border-b border-gray-200 last:border-0 dark:border-gray-700"
            >
              <td class="px-4 py-3"><StatusBadge :status="key" /></td>
              <td class="px-4 py-3">{{ statusTotals.map[key] || 0 }}</td>
              <td class="px-4 py-3 text-gray-500">
                {{
                  statusTotals.total
                    ? `${(((statusTotals.map[key] || 0) / statusTotals.total) * 100).toFixed(0)}%`
                    : '—'
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
