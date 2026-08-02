# TŞYS Web Paneli

Nuxt.js + Tailwind CSS arayüzü. Backend: aynı Supabase Cloud projesi (Flutter ile paylaşılır).

## Çalıştırma

```bash
cd web
npm install
npm run dev
```

Tarayıcı: http://localhost:3000

## Ortam

`web/.env` (örnek: `.env.example`):

- `NUXT_PUBLIC_SUPABASE_URL`
- `NUXT_PUBLIC_SUPABASE_ANON_KEY`
- `NUXT_PUBLIC_CACHE_API_URL` (opsiyonel — Render `tsys-api` adresi; boşsa doğrudan Supabase)

`service_role` anahtarı **asla** buraya konmaz.

## Render'a yayınlama (Static Site)

Repo kökünde `render.yaml` Blueprint dosyası var. İki yol:

### A) Blueprint (önerilen)

1. [dashboard.render.com](https://dashboard.render.com) → **New** → **Blueprint**
2. Bu GitHub reposunu seç (`talep_sorgu_cevap_app`, branch `main`)
3. `NUXT_PUBLIC_SUPABASE_URL` ve `NUXT_PUBLIC_SUPABASE_ANON_KEY` değerlerini (yerel `web/.env` ile aynı) gir
4. Apply / Create

Mevcut Blueprint varsa: Dashboard → Blueprint → **Manual Sync** / Apply (yeni `tsys-redis` Key Value oluşur).

### B) Manuel Static Site

1. **New** → **Static Site** → aynı repo / `main`
2. Ayarlar:

| Alan | Değer |
|------|--------|
| Root Directory | `web` |
| Build Command | `npm ci && npm run generate` |
| Publish Directory | `.output/public` |

3. Environment'a aynı iki `NUXT_PUBLIC_*` değişkenini ekle
4. **Redirects/Rewrites** → Rewrite: Source `/*` → Destination `/index.html`

> Not: Root Directory `web` iken Publish Directory her zaman `.output/public` olmalı.
> `./web/.output/public` yazarsan Render `web/web/.output/public` arar ve build fail olur.

### Deploy sonrası (zorunlu)

Supabase Dashboard → **Authentication → URL Configuration**:

- Redirect URLs'e ekle: `https://SENIN-SITE.onrender.com/**`
- İstersen Site URL'yi de buna güncelle

Giriş / şifre sıfırlama bu ayar olmadan bozulabilir.

## Redis (Render Key Value)

`render.yaml` içinde `tsys-redis` adında Redis-uyumlu **Key Value** (Valkey) tanımı var:

| Alan | Değer |
|------|--------|
| Plan | `free` |
| Politika | `allkeys-lru` (bellek dolunca eski anahtarlar silinir) |
| Ağ | `ipAllowList: []` — sadece aynı Render bölgesindeki servisler (internal) |

### Nasıl oluşturulur

1. Bu repoyu `main`'e push et
2. Render Dashboard → ilgili Blueprint → **Sync** / Apply  
   veya **New → Key Value** ile manuel: isim `tsys-redis`, Free plan, external access kapalı
3. Oluşunca **Internal Redis URL** Connect menüsünden görünür (`redis://...:6379`)

### Cache API (`tsys-api`)

Blueprint’te Node Web Service tanımlı (`api/`). Redis’e yalnızca bu servis bağlanır.

1. Blueprint Sync sonrası Dashboard’da **tsys-api** oluşur
2. Env doldur: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (anon key; service_role değil)
3. Deploy URL’ini kopyala → web `.env`: `NUXT_PUBLIC_CACHE_API_URL=https://tsys-api-....onrender.com`
4. Flutter `.env`: `CACHE_API_URL=https://tsys-api-....onrender.com`

Health: `GET https://tsys-api-....onrender.com/health` → `{ ok, redis: true }`

### Önemli mimari not

- **Static Site Redis'e bağlanamaz** — cache yalnızca `tsys-api` üzerinden.
- Flutter / Nuxt Redis URL’sini **asla** görmez; sadece public cache API adresini bilir.
- İsteklerde kullanıcı JWT’si gönderilir; Supabase RLS aynen uygulanır.
