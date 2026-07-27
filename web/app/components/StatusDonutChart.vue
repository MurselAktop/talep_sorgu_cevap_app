<script setup lang="ts">
import { Doughnut } from 'vue-chartjs'
import { Chart as ChartJS, ArcElement, Tooltip, Legend } from 'chart.js'
import { chartGrowAnimation } from '~/utils/chartAnimation'
import { ChartDataLabels, donutDataLabels } from '~/utils/chartLabels'

ChartJS.register(ArcElement, Tooltip, Legend, ChartDataLabels)

const props = defineProps<{
  labels: string[]
  values: number[]
  colors?: string[]
  playKey?: string | number
}>()

const defaultPalette = ['#F59E0B', '#3B82F6', '#14B8A6', '#EF4444', '#9CA3AF']

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
      data: shown.value,
      backgroundColor: props.values.map((_, i) => props.colors?.[i] || defaultPalette[i % defaultPalette.length]),
      borderWidth: 2,
      borderColor: 'rgba(17,24,39,0.35)',
    },
  ],
}))

const options = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  animation: {
    ...chartGrowAnimation,
    animateRotate: true,
    animateScale: true,
  },
  plugins: {
    legend: {
      position: 'bottom' as const,
      labels: { color: '#9CA3AF', boxWidth: 10, font: { size: 11 } },
    },
    datalabels: donutDataLabels,
  },
  cutout: '48%',
}))
</script>

<template>
  <div class="h-56">
    <Doughnut :key="`donut-${playKey ?? 'x'}`" :data="chartData" :options="options" />
  </div>
</template>
