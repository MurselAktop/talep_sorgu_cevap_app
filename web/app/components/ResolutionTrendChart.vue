<script setup lang="ts">
import { Line } from 'vue-chartjs'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Tooltip,
  Filler,
} from 'chart.js'
import { chartGrowAnimation } from '~/utils/chartAnimation'
import { ChartDataLabels, lineDataLabels } from '~/utils/chartLabels'

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Tooltip, Filler, ChartDataLabels)

const props = defineProps<{
  rows: Array<{
    period_start?: string
    month?: string
    period?: string
    avg_hours?: number
    avg_resolution_hours?: number
  }>
  playKey?: string | number
}>()

const labels = computed(() =>
  props.rows.map((r) => {
    const raw = String(r.period_start || r.month || r.period || '')
    try {
      const d = new Date(raw)
      if (!Number.isNaN(d.getTime())) {
        return d.toLocaleDateString('tr-TR', { month: 'short', year: 'numeric' })
      }
    } catch { /* ignore */ }
    return raw
  }),
)

const realValues = computed(() =>
  props.rows.map((r) => Number(r.avg_resolution_hours ?? r.avg_hours ?? 0)),
)

const shown = ref<number[]>([])

function kick() {
  shown.value = realValues.value.map(() => 0)
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      shown.value = [...realValues.value]
    })
  })
}

watch(() => [props.rows, props.playKey] as const, kick, { immediate: true, deep: true })

const chartData = computed(() => ({
  labels: labels.value,
  datasets: [
    {
      label: 'Ort. saat',
      data: shown.value,
      borderColor: '#3B82F6',
      backgroundColor: 'rgba(59,130,246,0.15)',
      fill: true,
      tension: 0.35,
      pointRadius: 4,
      pointHoverRadius: 6,
    },
  ],
}))

const options = {
  responsive: true,
  maintainAspectRatio: false,
  layout: { padding: { top: 18 } },
  animation: chartGrowAnimation,
  plugins: {
    legend: { display: false },
    datalabels: lineDataLabels,
  },
  scales: {
    x: { ticks: { color: '#9CA3AF', font: { size: 10 } }, grid: { color: 'rgba(156,163,175,0.15)' } },
    y: { ticks: { color: '#9CA3AF', font: { size: 10 } }, grid: { color: 'rgba(156,163,175,0.15)' }, beginAtZero: true },
  },
}
</script>

<template>
  <div class="h-56">
    <Line
      v-if="rows.length"
      :key="`trend-${playKey ?? 'x'}`"
      :data="chartData"
      :options="options"
    />
    <p v-else class="flex h-full items-center justify-center text-sm text-gray-500">Trend verisi yok.</p>
  </div>
</template>
