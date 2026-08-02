# TŞYS Cache API (`tsys-api`)

Render Web Service — Redis (Key Value) ile istatistik / birim listesi önbelleği.

```
Flutter / Nuxt  →  tsys-api  →  Redis
                      ↓
                   Supabase (kullanıcı JWT + RLS)
```

## Yerel çalıştırma

```bash
cd api
cp .env.example .env   # SUPABASE_* ve REDIS_URL doldur
npm install
npm run dev
```

Health: `GET http://localhost:8787/health`

## Uçlar

| Method | Path | Auth | Açıklama |
|--------|------|------|----------|
| GET | `/health` | yok | Servis + Redis durumu |
| GET | `/api/stats` | Bearer JWT | Admin/müdür istatistik paketi |
| GET | `/api/departments/active` | Bearer JWT | Aktif birimler |

Header: `Authorization: Bearer <supabase_access_token>`

## Render

Blueprint (`render.yaml`) `tsys-api` servisini tanımlar:

- `REDIS_URL` ← `tsys-redis` connectionString
- `SUPABASE_URL` / `SUPABASE_ANON_KEY` → Dashboard’da elle (sync: false)

Deploy sonrası Flutter `.env` ve web `.env`:

```
CACHE_API_URL=https://tsys-api-XXXX.onrender.com
NUXT_PUBLIC_CACHE_API_URL=https://tsys-api-XXXX.onrender.com
```

Boş bırakılırsa istemciler doğrudan Supabase RPC kullanmaya devam eder.
