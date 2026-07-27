<script setup lang="ts">
import { Bar } from 'vue-chartjs'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  Tooltip,
  Legend,
} from 'chart.js'
import { chartGrowAnimation, verticalBarAnimations } from '~/utils/chartAnimation'
import { ChartDataLabels, barCountDataLabels } from '~/utils/chartLabels'

ChartJS.register(CategoryScale, LinearScale, BarElement, Tooltip, Legend, ChartDataLabels)

const props = defineProps<{
  byDepartment: Record<string, Record<string, number>>
  pageSize?: number
  playKey?: string | number
}>()

const page = ref(0)
const pageSize = computed(() => props.pageSize ?? 3)
const deptNames = computed(() => Object.keys(props.byDepartment).sort((a, b) => a.localeCompare(b, 'tr')))
const pageCount = computed(() => Math.max(1, Math.ceil(deptNames.value.length / pageSize.value)))

watch(deptNames, () => {
  if (page.value >= pageCount.value) page.value = Math.max(0, pageCount.value - 1)
})

const pageDepts = computed(() => {
  const start = page.value * pageSize.value
  return deptNames.value.slice(start, start + pageSize.value)
})

const statuses = ['acik', 'cozuldu', 'onaylandi', 'reddedildi'] as const
const statusColors = {
  acik: '#F59E0B',
  cozuldu: '#3B82F6',
  onaylandi: '#14B8A6',
  reddedildi: '#EF4444',
}

const realDatasets = computed(() =>
  statuses.map((s) => ({
    label: statusLabels[s],
    data: pageDepts.value.map((d) => props.byDepartment[d]?.[s] || 0),
    backgroundColor: statusColors[s],
    borderRadius: 6,
    maxBarThickness: 28,
  })),
)

const shownDatasets = ref<typeof realDatasets.value>([])

function kick() {
  shownDatasets.value = realDatasets.value.map((ds) => ({
    ...ds,
    data: ds.data.map(() => 0),
  }))
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      shownDatasets.value = realDatasets.value.map((ds) => ({ ...ds, data: [...ds.data] }))
    })
  })
}

watch(
  () => [realDatasets.value, props.playKey, page.value] as const,
  kick,
  { immediate: true, deep: true },
)

const chartData = computed(() => ({
  labels: pageDepts.value,
  datasets: shownDatasets.value,
}))

const options = {
  responsive: true,
  maintainAspectRatio: false,
  animation: chartGrowAnimation,
  animations: verticalBarAnimations,
  plugins: {
    legend: { position: 'bottom' as const, labels: { color: '#9CA3AF', boxWidth: 10, font: { size: 10 } } },
    datalabels: {
      ...barCountDataLabels,
      font: { weight: 'bold' as const, size: 9 },
    },
  },
  scales: {
    x: {
      stacked: false,
      ticks: { color: '#9CA3AF', font: { size: 10 } },
      grid: { display: false },
    },
    y: {
      stacked: false,
      beginAtZero: true,
      ticks: { color: '#9CA3AF', font: { size: 10 }, precision: 0 },
      grid: { color: 'rgba(156,163,175,0.15)' },
    },
  },
}
</script>

<template>
  <div>
    <div class="h-64">
      <Bar
        v-if="pageDepts.length"
        :key="`dept-status-${playKey ?? 'x'}-${page}`"
        :data="chartData"
        :options="options"
      />
      <p v-else class="flex h-full items-center justify-center text-sm text-gray-500">Birim verisi yok.</p>
    </div>
    <div v-if="pageCount > 1" class="mt-3 flex justify-center gap-2">
      <button
        v-for="i in pageCount"
        :key="i"
        type="button"
        class="h-2.5 w-2.5 rounded-full transition-colors"
        :class="i - 1 === page ? 'bg-blue-600' : 'bg-gray-400/50 hover:bg-gray-400'"
        @click="page = i - 1"
      />
    </div>
  </div>
</template>
