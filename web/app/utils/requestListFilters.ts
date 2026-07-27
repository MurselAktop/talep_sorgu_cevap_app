/** Talep listesi sıralama + zaman aralığı filtreleri */

export type RequestSort = 'newest' | 'oldest'
export type RequestTimeRange = '' | '1h' | '1d' | '7d' | '30d'

export const requestSortOptions: { value: RequestSort; label: string }[] = [
  { value: 'newest', label: 'Yeniden eskiye' },
  { value: 'oldest', label: 'Eskiden yeniye' },
]

export const requestTimeRangeOptions: { value: RequestTimeRange; label: string }[] = [
  { value: '', label: 'Tüm zamanlar' },
  { value: '1h', label: 'Son 1 saat' },
  { value: '1d', label: 'Son 1 gün' },
  { value: '7d', label: 'Son 7 gün' },
  { value: '30d', label: 'Son 30 gün' },
]

export function timeRangeSince(range: RequestTimeRange): string | null {
  if (!range) return null
  const ms =
    range === '1h' ? 3600_000
    : range === '1d' ? 86_400_000
    : range === '7d' ? 7 * 86_400_000
    : range === '30d' ? 30 * 86_400_000
    : 0
  if (!ms) return null
  return new Date(Date.now() - ms).toISOString()
}

/** Supabase sorguya sıralama + created_at >= since uygular */
export function applyRequestListFilters<T extends { order: Function; gte: Function }>(
  query: T,
  opts: { sort: RequestSort; timeRange: RequestTimeRange },
): T {
  let q = query.order('created_at', { ascending: opts.sort === 'oldest' }) as T
  const since = timeRangeSince(opts.timeRange)
  if (since) q = q.gte('created_at', since) as T
  return q
}
