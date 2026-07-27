<script setup lang="ts">
import { Bar } from 'vue-chartjs'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  Tooltip,
} from 'chart.js'
import { chartGrowAnimation, verticalBarAnimations } from '~/utils/chartAnimation'
import { ChartDataLabels } from '~/utils/chartLabels'

ChartJS.register(CategoryScale, LinearScale, BarElement, Tooltip, ChartDataLabels)

const props = defineProps<{
  ratings: Record<string, number>
  pageSize?: number
  playKey?: string | number
}>()

const page = ref(0)
const pageSize = computed(() => props.pageSize ?? 3)
const names = computed(() => Object.keys(props.ratings).sort((a, b) => a.localeCompare(b, 'tr')))
const pageCount = computed(() => Math.max(1, Math.ceil(names.value.length / pageSize.value)))
const pageNames = computed(() => {
  const start = page.value * pageSize.value
  return names.value.slice(start, start + pageSize.value)
})

const realValues = computed(() =>
  pageNames.value.map((n) => Number(props.ratings[n]?.toFixed(2) ?? 0)),
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

watch(
  () => [realValues.value, props.playKey, page.value] as const,
  kick,
  { immediate: true, deep: true },
)

function barGradient(ctx: any) {
  const chart = ctx.chart
  const { ctx: c, chartArea } = chart
  if (!chartArea) return 'rgba(139, 92, 246, 0.85)'
  const g = c.createLinearGradient(0, chartArea.bottom, 0, chartArea.top)
  g.addColorStop(0, 'rgba(99, 102, 241, 0.35)')
  g.addColorStop(0.45, 'rgba(139, 92, 246, 0.75)')
  g.addColorStop(1, 'rgba(167, 139, 250, 0.95)')
  return g
}

const chartData = computed(() => ({
  labels: pageNames.value,
  datasets: [
    {
      label: 'Ortalama puan',
      data: shown.value,
      backgroundColor: barGradient,
      borderColor: 'rgba(167, 139, 250, 0.9)',
      borderWidth: 1,
      borderRadius: { topLeft: 10, topRight: 10, bottomLeft: 4, bottomRight: 4 },
      borderSkipped: false,
      maxBarThickness: 28,
      categoryPercentage: 0.45,
      barPercentage: 0.55,
    },
  ],
}))

const options = {
  responsive: true,
  maintainAspectRatio: false,
  layout: { padding: { top: 16, bottom: 4 } },
  animation: chartGrowAnimation,
  animations: verticalBarAnimations,
  plugins: {
    legend: { display: false },
    tooltip: {
      backgroundColor: 'rgba(15, 23, 42, 0.92)',
      titleFont: { size: 11 },
      bodyFont: { size: 12, weight: 'bold' as const },
      padding: 10,
      cornerRadius: 10,
      displayColors: false,
      callbacks: {
        label: (item: any) => `★ ${Number(item.raw).toFixed(1)} / 5`,
      },
    },
    datalabels: {
      display(ctx: any) {
        return Number(ctx.dataset.data[ctx.dataIndex] ?? 0) > 0
      },
      anchor: 'end' as const,
      align: 'top' as const,
      offset: 2,
      color: '#A78BFA',
      font: { weight: 'bold' as const, size: 11 },
      formatter(value: number) {
        const n = Number(value)
        return n > 0 ? n.toFixed(1) : ''
      },
    },
  },
  scales: {
    x: {
      ticks: {
        color: '#9CA3AF',
        font: { size: 11, weight: '500' as const },
        maxRotation: 0,
        autoSkip: false,
      },
      grid: { display: false },
      border: { display: false },
    },
    y: {
      min: 0,
      max: 5,
      ticks: {
        color: '#6B7280',
        font: { size: 10 },
        stepSize: 1,
        callback: (v: string | number) => `${v}`,
      },
      grid: {
        color: 'rgba(156,163,175,0.12)',
        drawTicks: false,
      },
      border: { display: false },
    },
  },
}
</script>

<template>
  <div>
    <div class="h-60">
      <Bar
        v-if="pageNames.length"
        :key="`dept-rating-${playKey ?? 'x'}-${page}`"
        :data="chartData"
        :options="options"
      />
      <p v-else class="flex h-full items-center justify-center text-sm text-gray-500">Puan verisi yok.</p>
    </div>
    <div v-if="pageCount > 1" class="mt-3 flex justify-center gap-2">
      <button
        v-for="i in pageCount"
        :key="i"
        type="button"
        class="h-2 rounded-full transition-all duration-200"
        :class="i - 1 === page ? 'w-5 bg-violet-500' : 'w-2 bg-gray-400/50 hover:bg-gray-400'"
        @click="page = i - 1"
      />
    </div>
  </div>
</template>
