/** Üst bardaki yenile — sayfa remount + rozet/bildirim tazeleme */
export function usePageRefresh() {
  const tick = useState('page-refresh-tick', () => 0)
  const refreshing = useState('page-refreshing', () => false)

  async function refresh(extra?: () => Promise<void> | void) {
    if (refreshing.value) return
    refreshing.value = true
    try {
      tick.value += 1
      await extra?.()
      // kısa spinner hissi
      await new Promise((r) => setTimeout(r, 280))
    } finally {
      refreshing.value = false
    }
  }

  return { tick, refreshing, refresh }
}
