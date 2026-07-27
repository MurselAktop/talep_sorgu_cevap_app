<script setup lang="ts">
const { user, isAdmin, isMudur, canViewIncoming } = useAuth()
const { openPanel: openDmPanel } = useDmPanel()
const supabase = useSupabase()

const statsRows = ref<any[]>([])
const trendRows = ref<any[]>([])
const personnelRatings = ref<any[]>([])
const recent = ref<any[]>([])
const loading = ref(true)
const tab = ref<'all' | 'acik' | 'cozuldu' | 'onaylandi'>('all')
const avgLabel = ref('—')
const animReady = ref(false)

const firstName = computed(() => {
  const full = user.value?.full_name?.trim() || 'Kullanıcı'
  return full.split(/\s+/)[0]
})

function countOf(row: any) {
  return Number(row.request_count ?? row.count ?? row.cnt ?? 0)
}

const totals = computed(() => {
  const map: Record<string, number> = { acik: 0, cozuldu: 0, onaylandi: 0, reddedildi: 0, iptal: 0 }
  let total = 0
  for (const row of statsRows.value) {
    const s = String(row.status || '')
    const c = countOf(row)
    if (s in map) map[s] += c
    total += c
  }
  return {
    total,
    pending: map.acik,
    resolved: map.onaylandi + map.cozuldu,
    ...map,
  }
})

const statusOrder = ['acik', 'cozuldu', 'onaylandi', 'reddedildi'] as const
const statusColorMap: Record<string, string> = {
  acik: '#F59E0B',
  cozuldu: '#3B82F6',
  onaylandi: '#14B8A6',
  reddedildi: '#EF4444',
}

const chartLabels = computed(() => statusOrder.map((k) => statusLabels[k] || k))
const chartValues = computed(() => statusOrder.map((k) => totals.value[k] || 0))
const chartColors = statusOrder.map((k) => statusColorMap[k])

const barLabels = computed(() => chartLabels.value)
const barValues = computed(() => chartValues.value)

const byDepartment = computed(() => {
  const out: Record<string, Record<string, number>> = {}
  for (const row of statsRows.value) {
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

const showFullCharts = computed(() => isAdmin.value || isMudur.value)

const chartSlides = computed(() => {
  const slides = [
    { id: 'donut', label: 'Durum Dağılımı', short: 'Dağılım' },
    { id: 'statusBar', label: 'Durumlara Göre Adet', short: 'Durum' },
  ]
  if (showFullCharts.value) {
    slides.push({ id: 'trend', label: 'Aylık Ortalama Çözüm Süresi', short: 'Süre' })
  }
  if (isAdmin.value) {
    slides.push(
      { id: 'deptStatus', label: 'Birim × Durum', short: 'Birim' },
      { id: 'deptRating', label: 'Birim Bazlı Ortalama Puan', short: 'Puan' },
    )
  }
  return slides
})

const filteredRecent = computed(() => {
  if (tab.value === 'all') return recent.value
  return recent.value.filter((r) => r.status === tab.value)
})

const quickActions = computed(() => {
  const items = [
    { to: '/requests/create', action: null as string | null, label: 'Yeni Talep Oluştur', desc: 'Arıza veya talep kaydı aç', icon: 'create', show: true },
    { to: '/requests/mine', action: null, label: 'Taleplerim', desc: 'Kendi taleplerinizi izleyin', icon: 'mine', show: true },
    { to: null, action: 'openDm', label: 'Mesajlar', desc: 'Kurum içi DM kutusu', icon: 'messages', show: canViewIncoming.value },
    { to: '/stats', action: null, label: 'Raporlar', desc: 'İstatistik ve özetler', icon: 'chart', show: isAdmin.value || isMudur.value },
  ]
  return items.filter((i) => i.show)
})

function onQuickAction(a: { action: string | null; to: string | null }) {
  if (a.action === 'openDm') {
    openDmPanel()
    return
  }
  if (a.to) navigateTo(a.to)
}

async function load() {
  loading.value = true
  animReady.value = false
  try {
    void supabase.rpc('purge_expired_requests')
    if (isMudur.value) void supabase.rpc('check_sla_breaches')

    if (isAdmin.value || isMudur.value) {
      const rpc = isAdmin.value ? 'get_admin_stats' : 'get_manager_stats'
      const trendRpc = isAdmin.value ? 'get_admin_resolution_trend' : 'get_manager_resolution_trend'
      const [statsRes, trendRes, ratingsRes] = await Promise.all([
        supabase.rpc(rpc),
        supabase.rpc(trendRpc),
        supabase.rpc('get_personnel_ratings'),
      ])
      statsRows.value = Array.isArray(statsRes.data) ? statsRes.data : []
      trendRows.value = Array.isArray(trendRes.data) ? trendRes.data : []
      personnelRatings.value = Array.isArray(ratingsRes.data) ? ratingsRes.data : []

      const last = trendRows.value[trendRows.value.length - 1]
      const hours = Number(last?.avg_resolution_hours ?? last?.avg_hours ?? NaN)
      if (!Number.isNaN(hours) && hours > 0) {
        const h = Math.floor(hours)
        const m = Math.round((hours - h) * 60)
        avgLabel.value = `${h}s ${m}dk`
      } else {
        avgLabel.value = '—'
      }
    }

    let q = supabase
      .from('requests')
      .select('id, title, status, created_at, departments(name)')
      .order('created_at', { ascending: false })
      .limit(8)

    if (user.value?.role === 'personel') q = q.eq('assigned_to', user.value.id)
    else if (user.value?.role === 'mudur') q = q.eq('department_id', user.value.department_id)
    else if (user.value?.role === 'vatandas') q = q.eq('created_by', user.value.id)

    const { data } = await q
    recent.value = data || []

    if (!isAdmin.value && !isMudur.value) {
      const all = recent.value
      statsRows.value = [
        { status: 'acik', count: all.filter((r) => r.status === 'acik').length },
        { status: 'cozuldu', count: all.filter((r) => r.status === 'cozuldu').length },
        { status: 'onaylandi', count: all.filter((r) => r.status === 'onaylandi').length },
        { status: 'reddedildi', count: all.filter((r) => r.status === 'reddedildi').length },
      ]
    }
  } finally {
    loading.value = false
    await nextTick()
    animReady.value = true
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-6">
    <h1 class="text-xl font-semibold text-gray-900 dark:text-white md:text-2xl">
      Merhaba {{ firstName }}, Hoş Geldin!
    </h1>

    <!-- Quick actions -->
    <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
      <button
        v-for="a in quickActions"
        :key="a.label"
        type="button"
        class="card group flex items-center gap-3.5 p-3.5 text-left transition-all duration-150 hover:border-blue-500/40 hover:shadow-[0_4px_16px_rgba(37,99,235,0.12)]"
        @click="onQuickAction(a)"
      >
        <span
          class="rounded-xl p-3"
          :class="a.icon === 'messages' ? 'bg-amber-500/15 text-amber-500' : 'bg-blue-600/15 text-blue-600 dark:text-blue-400'"
        >
          <svg v-if="a.icon === 'create'" class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M12 5v14M5 12h14" />
          </svg>
          <svg v-else-if="a.icon === 'mine'" class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01" />
          </svg>
          <svg v-else-if="a.icon === 'messages'" class="h-6 w-6" viewBox="0 0 24 24" fill="currentColor">
            <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z" />
          </svg>
          <svg v-else class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M4 19V5M4 19h16M8 17V9M12 17V7M16 17v-4" />
          </svg>
        </span>
        <div>
          <p class="text-[13px] font-semibold text-gray-900 group-hover:text-blue-600 dark:text-white dark:group-hover:text-blue-400">
            {{ a.label }}
          </p>
          <p class="text-[11px] leading-4 text-gray-500 dark:text-gray-400">{{ a.desc }}</p>
        </div>
      </button>
    </div>

    <!-- KPI cards -->
    <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <div class="card p-4">
        <div class="mb-3 flex items-center justify-between">
          <span class="text-[12px] text-gray-500">Toplam Arıza</span>
          <span class="rounded-lg bg-red-500/20 p-2 text-red-400">
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" />
            </svg>
          </span>
        </div>
        <p class="text-3xl font-semibold text-gray-900 dark:text-white">
          <AnimatedNumber v-if="animReady" :value="totals.total" />
          <span v-else>0</span>
        </p>
      </div>
      <div class="card p-4">
        <div class="mb-3 flex items-center justify-between">
          <span class="text-[12px] text-gray-500">Bekleyen</span>
          <span class="rounded-lg bg-amber-500/20 p-2 text-amber-400">
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <rect x="3" y="4" width="18" height="18" rx="2" /><path d="M16 2v4M8 2v4M3 10h18" />
            </svg>
          </span>
        </div>
        <p class="text-3xl font-semibold text-gray-900 dark:text-white">
          <AnimatedNumber v-if="animReady" :value="totals.pending" />
          <span v-else>0</span>
        </p>
      </div>
      <div class="card p-4">
        <div class="mb-3 flex items-center justify-between">
          <span class="text-[12px] text-gray-500">Çözülen</span>
          <span class="rounded-lg bg-teal-500/20 p-2 text-teal-400">
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M20 6 9 17l-5-5" />
            </svg>
          </span>
        </div>
        <p class="text-3xl font-semibold text-gray-900 dark:text-white">
          <AnimatedNumber v-if="animReady" :value="totals.resolved" />
          <span v-else>0</span>
        </p>
      </div>
      <div class="card p-4">
        <div class="mb-3 flex items-center justify-between">
          <span class="text-[12px] text-gray-500">Ort. Çözüm Süresi</span>
          <span class="rounded-lg bg-blue-500/20 p-2 text-blue-400">
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" />
            </svg>
          </span>
        </div>
        <p class="text-3xl font-semibold text-gray-900 dark:text-white">
          {{ loading ? '—' : avgLabel }}
        </p>
      </div>
    </div>

    <div
      v-if="isMudur && managerAvgRating != null"
      class="card flex items-center justify-between gap-3 p-4"
    >
      <div>
        <p class="text-[12px] text-gray-500">Birimin Ortalama Değerlendirme</p>
        <p class="text-2xl font-semibold text-amber-500">★ {{ managerAvgRating.toFixed(1) }}</p>
      </div>
      <NuxtLink to="/stats" class="btn-secondary text-xs">Detaylı raporlar</NuxtLink>
    </div>

    <!-- Grafikler: yuvarlak sekmeler + kaydırarak geçiş -->
    <DashboardChartsCarousel :slides="chartSlides">
      <template #donut="{ active, playKey }">
        <StatusDonutChart
          v-if="animReady && active && chartValues.some((v) => v > 0)"
          :labels="chartLabels"
          :values="chartValues"
          :colors="chartColors"
          :play-key="playKey"
        />
        <p v-else-if="active" class="py-16 text-center text-sm text-gray-500">Grafik için veri yok.</p>
      </template>
      <template #statusBar="{ active, playKey }">
        <StatusBarChart
          v-if="animReady && active"
          :labels="barLabels"
          :values="barValues"
          :colors="chartColors"
          :play-key="playKey"
        />
      </template>
      <template #trend="{ active, playKey }">
        <ResolutionTrendChart v-if="active" :rows="trendRows" :play-key="playKey" />
      </template>
      <template #deptStatus="{ active, playKey }">
        <DeptStatusBarChart v-if="active" :by-department="byDepartment" :play-key="playKey" />
      </template>
      <template #deptRating="{ active, playKey }">
        <DeptRatingBarChart v-if="active" :ratings="departmentRatings" :play-key="playKey" />
      </template>
    </DashboardChartsCarousel>

    <!-- Son talepler -->
    <div class="card overflow-hidden">
      <div class="flex flex-wrap items-center justify-between gap-3 border-b border-gray-200 px-4 py-3 dark:border-gray-700">
        <h2 class="text-[13px] font-semibold text-gray-900 dark:text-white">Son Talepler</h2>
        <NuxtLink to="/requests/create" class="btn-primary text-xs sm:text-sm">Yeni Talep Ekle</NuxtLink>
      </div>
      <div class="flex gap-1 overflow-x-auto border-b border-gray-200 px-3 py-2 dark:border-gray-700">
        <button
          v-for="t in [
            { id: 'all', label: 'Tümü' },
            { id: 'acik', label: 'Bekleyen' },
            { id: 'cozuldu', label: 'İşlemde' },
            { id: 'onaylandi', label: 'Çözüldü' },
          ]"
          :key="t.id"
          type="button"
          class="rounded-lg px-3 py-1.5 text-xs font-medium transition-colors duration-150"
          :class="tab === t.id
            ? 'bg-blue-600/15 text-blue-600 dark:text-blue-400'
            : 'text-gray-500 hover:bg-gray-200/70 dark:text-gray-400 dark:hover:bg-gray-700/60'"
          @click="tab = t.id as typeof tab"
        >
          {{ t.label }}
        </button>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full min-w-[560px] text-left text-sm">
          <thead>
            <tr class="border-b border-gray-200 text-xs uppercase text-gray-500 dark:border-gray-700 dark:text-gray-400">
              <th class="px-4 py-3 font-medium">Başlık</th>
              <th class="px-4 py-3 font-medium">Bölüm</th>
              <th class="px-4 py-3 font-medium">Durum</th>
              <th class="px-4 py-3 font-medium">Tarih</th>
              <th class="px-4 py-3 font-medium" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="r in filteredRecent"
              :key="r.id"
              class="border-b border-gray-200 last:border-0 dark:border-gray-700"
            >
              <td class="px-4 py-3 font-medium text-gray-900 dark:text-gray-100">{{ r.title }}</td>
              <td class="px-4 py-3 text-gray-600 dark:text-gray-300">{{ r.departments?.name || '—' }}</td>
              <td class="px-4 py-3"><StatusBadge :status="r.status" /></td>
              <td class="px-4 py-3 text-gray-500">{{ new Date(r.created_at).toLocaleDateString('tr-TR') }}</td>
              <td class="px-4 py-3">
                <NuxtLink :to="`/requests/${r.id}`" class="text-xs text-blue-600 hover:underline dark:text-blue-400">
                  Detay
                </NuxtLink>
              </td>
            </tr>
            <tr v-if="!loading && !filteredRecent.length">
              <td colspan="5" class="px-4 py-8 text-center text-sm text-gray-500">Kayıt bulunamadı.</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
