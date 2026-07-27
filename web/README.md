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
