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

> Not: Dashboard'da Publish Directory genelde Root Directory'ye göredir (`.output/public`). Blueprint'te path repo köküne göredir (`./web/.output/public`).

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

### Önemli mimari not

- **Static Site (`tsys-web`) Redis'e bağlanamaz** — tarayıcıda çalışan SPA'nın sunucu tarafı yok.
- Flutter / Nuxt istemcileri Redis URL'sini **asla** görmemeli (güvenlik).
- Redis'i kullanmak için sonraki adım: aynı Render workspace + **aynı region**'da bir Web Service (veya Background Worker) yazıp `REDIS_URL`'i `fromService` ile bağlamak; istatistik / sık okunan RPC sonuçlarını orada cache'lemek.

Örnek (ileride eklenecek bir Node servisi için Blueprint parçası):

```yaml
envVars:
  - key: REDIS_URL
    fromService:
      name: tsys-redis
      type: keyvalue
      property: connectionString
```
