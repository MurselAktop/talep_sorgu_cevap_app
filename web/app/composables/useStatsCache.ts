/**
 * Render tsys-api üzerinden Redis cache'li istatistik yükler.
 * NUXT_PUBLIC_CACHE_API_URL yoksa veya istek düşerse doğrudan Supabase RPC.
 */
export async function fetchDashboardStats(opts: {
  isAdmin: boolean
  accessToken: string
}) {
  const config = useRuntimeConfig()
  const base = String(config.public.cacheApiUrl || '').replace(/\/$/, '')
  const supabase = useSupabase()

  if (base && opts.accessToken) {
    try {
      const res = await fetch(`${base}/api/stats`, {
        headers: {
          Authorization: `Bearer ${opts.accessToken}`,
          Accept: 'application/json',
        },
      })
      if (res.ok) {
        const body = await res.json()
        if (Array.isArray(body?.rows)) {
          return {
            rows: body.rows as any[],
            trendRows: (body.trendRows as any[]) || [],
            personnelRatings: (body.personnelRatings as any[]) || [],
            cached: !!body.cached,
            error: '',
          }
        }
      }
    } catch {
      // fallback below
    }
  }

  const statsRpc = opts.isAdmin ? 'get_admin_stats' : 'get_manager_stats'
  const trendRpc = opts.isAdmin ? 'get_admin_resolution_trend' : 'get_manager_resolution_trend'
  const results = await Promise.all([
    supabase.rpc(statsRpc),
    supabase.rpc(trendRpc),
    supabase.rpc('get_personnel_ratings'),
  ])

  return {
    rows: Array.isArray(results[0].data) ? results[0].data : [],
    trendRows: Array.isArray(results[1].data) ? results[1].data : [],
    personnelRatings: Array.isArray(results[2].data) ? results[2].data : [],
    cached: false,
    error: results[0].error?.message || '',
  }
}
