/** Chart.js — çubuk/çizgi/pasta sıfırdan büyüsün */
export const chartGrowAnimation = {
  duration: 1100,
  easing: 'easeOutQuart' as const,
}

/** Yatay çubuk (indexAxis: 'y') — soldan sağa uzasın */
export const horizontalBarAnimations = {
  x: {
    type: 'number' as const,
    easing: 'easeOutQuart' as const,
    duration: 1100,
    from: (_ctx: unknown) => 0,
  },
}

/** Dikey çubuk — alttan yukarı uzasın */
export const verticalBarAnimations = {
  y: {
    type: 'number' as const,
    easing: 'easeOutQuart' as const,
    duration: 1100,
    from: (_ctx: unknown) => 0,
  },
}
