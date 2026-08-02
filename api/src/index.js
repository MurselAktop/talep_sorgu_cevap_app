import cors from 'cors'
import express from 'express'
import Redis from 'ioredis'
import { createClient } from '@supabase/supabase-js'

const PORT = Number(process.env.PORT || 8787)
const SUPABASE_URL = process.env.SUPABASE_URL || ''
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || ''
const STATS_TTL = Number(process.env.STATS_CACHE_TTL_SECONDS || 60)

/** Internal URL veya host:port (Blueprint fromService). */
function resolveRedisUrl() {
  const direct = (process.env.REDIS_URL || '').trim()
  if (direct) return direct
  const host = (process.env.REDIS_HOST || process.env.REDIS_SERVICE_NAME || '').trim()
  if (!host) return ''
  const port = (process.env.REDIS_PORT || '6379').trim()
  return `redis://${host}:${port}`
}

const REDIS_URL = resolveRedisUrl()

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error('SUPABASE_URL ve SUPABASE_ANON_KEY zorunlu.')
  process.exit(1)
}

/** @type {import('ioredis').Redis | null} */
let redis = null
let redisReady = false
/** @type {string | null} */
let redisLastError = null

function redisHostHint() {
  if (!REDIS_URL) return null
  try {
    return new URL(REDIS_URL).host
  } catch {
    return '(parse-failed)'
  }
}

function initRedis() {
  if (!REDIS_URL) {
    redisLastError = 'REDIS_URL env yok — Dashboard > tsys-api > Environment kontrol et'
    console.warn(redisLastError)
    return
  }

  // Render Key Value: internal redis://red-xxx:6379
  // ioredis, Render dokümantasyonunun önerdiği istemci.
  redis = new Redis(REDIS_URL, {
    maxRetriesPerRequest: 2,
    enableReadyCheck: true,
    // Render private network / DNS için
    family: 0,
    connectTimeout: 15_000,
    lazyConnect: false,
    retryStrategy(times) {
      if (times > 8) return null
      return Math.min(times * 200, 2000)
    },
  })

  redis.on('ready', () => {
    redisReady = true
    redisLastError = null
    console.log('Redis hazır:', redisHostHint())
  })

  redis.on('error', (err) => {
    redisReady = false
    redisLastError = err.message
    console.error('Redis error:', err.message)
  })

  redis.on('end', () => {
    redisReady = false
    console.warn('Redis bağlantısı kapandı.')
  })
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
  } catch (err) {
    redisLastError = err.message
    return null
  }
}

async function cacheSet(key, value, ttlSec) {
  if (!redisReady || !redis) return
  try {
    await redis.set(key, JSON.stringify(value), 'EX', ttlSec)
  } catch (err) {
    redisLastError = err.message
    console.error('Redis set hata:', err.message)
  }
}

const app = express()
app.use(cors({ origin: true }))
app.use(express.json({ limit: '256kb' }))

app.get('/health', async (_req, res) => {
  // Hazır değilse tek seferlik PING dene (soğuk başlangıç)
  if (redis && !redisReady) {
    try {
      const pong = await redis.ping()
      if (pong === 'PONG') {
        redisReady = true
        redisLastError = null
      }
    } catch (err) {
      redisLastError = err.message
    }
  }

  res.json({
    ok: true,
    service: 'tsys-api',
    redis: redisReady,
    redisConfigured: Boolean(REDIS_URL),
    redisHost: redisHostHint(),
    redisError: redisReady ? null : redisLastError,
  })
})

/**
 * GET /api/stats
 * Admin veya müdür JWT ile istatistik paketini döner (cache-aside).
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

initRedis()
app.listen(PORT, () => {
  console.log(
    `tsys-api dinleniyor :${PORT} redisConfigured=${Boolean(REDIS_URL)} host=${redisHostHint()}`,
  )
})
