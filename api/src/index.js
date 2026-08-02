import cors from 'cors'
import express from 'express'
import { createClient } from '@supabase/supabase-js'
import { createClient as createRedisClient } from 'redis'

const PORT = Number(process.env.PORT || 8787)
const SUPABASE_URL = process.env.SUPABASE_URL || ''
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || ''
const REDIS_URL = process.env.REDIS_URL || ''
const STATS_TTL = Number(process.env.STATS_CACHE_TTL_SECONDS || 60)

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error('SUPABASE_URL ve SUPABASE_ANON_KEY zorunlu.')
  process.exit(1)
}

/** @type {import('redis').RedisClientType | null} */
let redis = null
let redisReady = false

async function initRedis() {
  if (!REDIS_URL) {
    console.warn('REDIS_URL yok — cache kapalı, doğrudan Supabase kullanılacak.')
    return
  }
  try {
    redis = createRedisClient({ url: REDIS_URL })
    redis.on('error', (err) => {
      console.error('Redis error:', err.message)
      redisReady = false
    })
    await redis.connect()
    redisReady = true
    console.log('Redis bağlandı.')
  } catch (err) {
    console.error('Redis bağlanamadı, cache kapalı:', err.message)
    redis = null
    redisReady = false
  }
}

function supabaseAsUser(accessToken) {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: {
      headers: { Authorization: `Bearer ${accessToken}` },
    },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  })
}

function bearer(req) {
  const h = req.headers.authorization || ''
  const m = /^Bearer\s+(.+)$/i.exec(h)
  return m?.[1]?.trim() || null
}

async function requireUser(req, res) {
  const token = bearer(req)
  if (!token) {
    res.status(401).json({ error: 'Authorization Bearer token gerekli.' })
    return null
  }
  const supabase = supabaseAsUser(token)
  const { data, error } = await supabase.auth.getUser(token)
  if (error || !data?.user) {
    res.status(401).json({ error: 'Geçersiz veya süresi dolmuş oturum.' })
    return null
  }
  const { data: profile, error: profileError } = await supabase
    .from('users')
    .select('id, role, department_id, is_active')
    .eq('id', data.user.id)
    .maybeSingle()
  if (profileError || !profile) {
    res.status(403).json({ error: 'Kullanıcı profili bulunamadı.' })
    return null
  }
  if (profile.is_active === false) {
    res.status(403).json({ error: 'Hesap pasif.' })
    return null
  }
  return { token, supabase, user: data.user, profile }
}

async function cacheGet(key) {
  if (!redisReady || !redis) return null
  try {
    const raw = await redis.get(key)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

async function cacheSet(key, value, ttlSec) {
  if (!redisReady || !redis) return
  try {
    await redis.set(key, JSON.stringify(value), { EX: ttlSec })
  } catch (err) {
    console.error('Redis set hata:', err.message)
  }
}

const app = express()
app.use(cors({ origin: true }))
app.use(express.json({ limit: '256kb' }))

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    redis: redisReady,
    service: 'tsys-api',
  })
})

/**
 * GET /api/stats
 * Admin veya müdür JWT ile istatistik paketini döner (cache-aside).
 * Body: { rows, trendRows, personnelRatings, cached }
 */
app.get('/api/stats', async (req, res) => {
  try {
    const ctx = await requireUser(req, res)
    if (!ctx) return

    const role = ctx.profile.role
    if (role !== 'admin' && role !== 'mudur') {
      return res.status(403).json({ error: 'İstatistikler yalnızca admin/müdür için.' })
    }

    const cacheKey = `stats:v1:${ctx.profile.id}`
    const hit = await cacheGet(cacheKey)
    if (hit) {
      return res.json({ ...hit, cached: true })
    }

    const statsRpc = role === 'admin' ? 'get_admin_stats' : 'get_manager_stats'
    const trendRpc =
      role === 'admin' ? 'get_admin_resolution_trend' : 'get_manager_resolution_trend'

    const [statsRes, trendRes, ratingsRes] = await Promise.all([
      ctx.supabase.rpc(statsRpc),
      ctx.supabase.rpc(trendRpc),
      ctx.supabase.rpc('get_personnel_ratings'),
    ])

    if (statsRes.error) {
      return res.status(400).json({ error: statsRes.error.message })
    }
    if (trendRes.error) {
      return res.status(400).json({ error: trendRes.error.message })
    }
    if (ratingsRes.error) {
      return res.status(400).json({ error: ratingsRes.error.message })
    }

    const payload = {
      rows: statsRes.data ?? [],
      trendRows: trendRes.data ?? [],
      personnelRatings: ratingsRes.data ?? [],
    }
    await cacheSet(cacheKey, payload, STATS_TTL)
    return res.json({ ...payload, cached: false })
  } catch (err) {
    console.error('/api/stats', err)
    return res.status(500).json({ error: 'İstatistikler yüklenemedi.' })
  }
})

/**
 * GET /api/departments/active
 * Aktif birim listesi (kısa TTL cache) — giriş yapmış herkes.
 */
app.get('/api/departments/active', async (req, res) => {
  try {
    const ctx = await requireUser(req, res)
    if (!ctx) return

    const cacheKey = 'departments:active:v1'
    const hit = await cacheGet(cacheKey)
    if (hit) {
      return res.json({ departments: hit, cached: true })
    }

    const { data, error } = await ctx.supabase
      .from('departments')
      .select('id, name')
      .eq('is_active', true)
      .order('name')

    if (error) {
      return res.status(400).json({ error: error.message })
    }

    const departments = data ?? []
    await cacheSet(cacheKey, departments, Math.max(STATS_TTL, 120))
    return res.json({ departments, cached: false })
  } catch (err) {
    console.error('/api/departments/active', err)
    return res.status(500).json({ error: 'Birimler yüklenemedi.' })
  }
})

await initRedis()
app.listen(PORT, () => {
  console.log(`tsys-api dinleniyor :${PORT} (redis=${redisReady})`)
})
