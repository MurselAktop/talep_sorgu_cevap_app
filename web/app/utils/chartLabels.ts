import type { ChartType } from 'chart.js'
import ChartDataLabels from 'chartjs-plugin-datalabels'

/** Pasta: dilim içinde yüzde (küçük dilimleri gizle) */
export const donutDataLabels = {
  display(ctx: any) {
    const v = Number(ctx.dataset.data[ctx.dataIndex] ?? 0)
    const total = (ctx.dataset.data as number[]).reduce((a, b) => a + Number(b || 0), 0)
    if (!total || v <= 0) return false
    return (v / total) * 100 >= 5
  },
  color: '#fff',
  font: { weight: 'bold' as const, size: 11 },
  formatter(value: number, ctx: any) {
    const total = (ctx.dataset.data as number[]).reduce((a: number, b: number) => a + Number(b || 0), 0)
    if (!total) return ''
    const pct = Math.round((Number(value) / total) * 100)
    return `${pct}%\n${value}`
  },
  textAlign: 'center' as const,
  anchor: 'center' as const,
  clamp: true,
}

/** Yatay / dikey çubuk: değer (0 gizle) */
export const barCountDataLabels = {
  display(ctx: any) {
    return Number(ctx.dataset.data[ctx.dataIndex] ?? 0) > 0
  },
  color: '#fff',
  font: { weight: 'bold' as const, size: 10 },
  anchor: 'center' as const,
  align: 'center' as const,
  clamp: true,
  formatter(value: number) {
    return Number(value) > 0 ? String(Math.round(Number(value))) : ''
  },
}

/** Dikey puan çubuğu */
export const barRatingDataLabels = {
  display(ctx: any) {
    return Number(ctx.dataset.data[ctx.dataIndex] ?? 0) > 0
  },
  color: '#fff',
  font: { weight: 'bold' as const, size: 11 },
  anchor: 'center' as const,
  align: 'center' as const,
  formatter(value: number) {
    const n = Number(value)
    return n > 0 ? n.toFixed(1) : ''
  },
}

/** Çizgi grafik: nokta üstünde değer */
export const lineDataLabels = {
  display(ctx: any) {
    return Number(ctx.dataset.data[ctx.dataIndex] ?? 0) > 0
  },
  color: '#60A5FA',
  backgroundColor: 'rgba(15, 23, 42, 0.75)',
  borderRadius: 4,
  padding: { top: 2, bottom: 2, left: 4, right: 4 },
  font: { weight: 'bold' as const, size: 10 },
  anchor: 'end' as const,
  align: 'top' as const,
  formatter(value: number) {
    const n = Number(value)
    if (!n) return ''
    return Number.isInteger(n) ? String(n) : n.toFixed(1)
  },
}

export { ChartDataLabels }
export type { ChartType }
