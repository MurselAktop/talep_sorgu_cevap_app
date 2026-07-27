<script setup lang="ts">
import { Bar } from 'vue-chartjs'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  Tooltip,
} from 'chart.js'
import { chartGrowAnimation, horizontalBarAnimations } from '~/utils/chartAnimation'
import { ChartDataLabels, barCountDataLabels } from '~/utils/chartLabels'

ChartJS.register(CategoryScale, LinearScale, BarElement, Tooltip, ChartDataLabels)

const props = defineProps<{
  labels: string[]
  values: number[]
  colors?: string[]
  playKey?: string | number
}>()

const shown = ref<number[]>(props.values.map(() => 0))

function kick() {
  shown.value = props.values.map(() => 0)
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      shown.value = [...props.values]
    })
  })
}

watch(() => [props.values, props.playKey] as const, kick, { immediate: true, deep: true })

const chartData = computed(() => ({
  labels: props.labels,
  datasets: [
    {
      label: 'Adet',
      data: shown.value,
      backgroundColor: props.values.map(
        (_, i) => props.colors?.[i] || '#3B82F6',
      ),
      borderRadius: 8,
      barThickness: 36,
    },
  ],
}))

const options = {
  indexAxis: 'y' as const,
  responsive: true,
  maintainAspectRatio: false,
  animation: chartGrowAnimation,
  animations: horizontalBarAnimations,
  plugins: {
    legend: { display: false },
    datalabels: barCountDataLabels,
  },
  scales: {
    x: {
      beginAtZero: true,
      ticks: { color: '#9CA3AF', font: { size: 10 }, precision: 0 },
      grid: { color: 'rgba(156,163,175,0.15)' },
    },
    y: {
      ticks: { color: '#9CA3AF', font: { size: 11 } },
      grid: { display: false },
    },
  },
}
</script>

<template>
  <div class="h-56">
    <Bar
      v-if="values.some((v) => v > 0)"
      :key="`bar-${playKey ?? 'x'}`"
      :data="chartData"
      :options="options"
    />
    <p v-else class="flex h-full items-center justify-center text-sm text-gray-500">Veri yok.</p>
  </div>
</template>
