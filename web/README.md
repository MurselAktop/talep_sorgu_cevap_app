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
