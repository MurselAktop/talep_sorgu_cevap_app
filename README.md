# TŞYS — Talep ve Şikâyet Yönetim Sistemi

Vatandaşların ve kurum personelinin arıza / talep / şikâyet bildirdiği; ilgili birime yönlendirilen; personelin çözüp raporladığı; birim müdürünün onayladığı veya reddettiği bir **mobil + web** yönetim uygulamasıdır.

**Depo:** `talep_sorgu_cevap_app`  
**Görünen ad:** TŞYS — Talep ve Şikâyet Yönetim Sistemi

## Özellikler (özet)

- Hibrit vatandaş erişimi: hesaplı giriş veya anonim talep + erişim kodu ile sorgulama
- Personel / müdür / admin kaydı: admin’in ürettiği davet kodu ile
- Talep döngüsü: oluştur → müdür atar → personel çözer → müdür onaylar/reddeder → bildirim
- Medya ekleri (foto / video / belge), SLA, istatistik, puanlama, yeniden açma, talep geçmişi
- Kurum içi DM (personel↔müdür, müdür↔admin)
- Gemini tabanlı Arıza Talep Asistanı (API anahtarı yalnızca Edge Function secret’ı)
- Yetkilendirme istemci `if` bloklarında değil; **PostgreSQL RLS** ile

## Teknoloji yığını

| Katman | Teknoloji |
|--------|-----------|
| Mobil | Flutter (`lib/`) |
| Web yönetim paneli | Nuxt 4 + Tailwind + Chart.js (`web/`) — personel/müdür/admin |
| Backend | Supabase Cloud (Auth, Postgres, Storage, RLS, RPC, Edge Functions) |
| Önbellek | Redis uyumlu Render Key Value + Node cache API (`api/` → `tsys-api`) |
| Dağıtım | Web: Render Static Site (`tsys-web`); API: Render Web Service |

Vatandaş kapsamı web panelde yoktur; mobil uygulamada kalır.

## Roller

| Rol | Yetki özeti |
|-----|-------------|
| **Vatandaş** | Talep açar; yalnızca kendi taleplerini görür |
| **Personel** | Kendisine atanan (`assigned_to`) talepleri çözer; rapor yazar |
| **Müdür** | Biriminin tüm taleplerini görür; atar; raporu onaylar/reddeder |
| **Admin** | Sistem geneli: birim/kullanıcı, davet kodu, müdahale |

## Depo yapısı

```text
lib/                 Flutter mobil uygulama
web/                 Nuxt web yönetim paneli
api/                 Cache API (istatistik paketleri)
supabase/
  migrations/        SQL şema + RLS + RPC
  functions/         Edge Functions (örn. analyze-request)
render.yaml          Render Blueprint
```

## Kurulum (mobil)

1. Flutter SDK kurulu olsun.
2. Kökte `.env` oluştur (şablon: `.env.example`):

```env
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
CACHE_API_URL=          # opsiyonel; boşsa doğrudan Supabase RPC
```

3. Çalıştır:

```bash
flutter pub get
flutter run
```

`service_role` anahtarı **asla** Flutter veya web istemcisine konmaz. Gemini anahtarı yalnızca Supabase Edge Function secret’ıdır.

## Web paneli

Ayrıntılar: [`web/README.md`](web/README.md)

```bash
cd web
npm install
cp .env.example .env   # NUXT_PUBLIC_SUPABASE_URL / ANON_KEY
npm run dev
```

## Cache API

Ayrıntılar: [`api/README.md`](api/README.md)

`CACHE_API_URL` / `NUXT_PUBLIC_CACHE_API_URL` boş bırakılırsa istemciler istatistik için doğrudan Supabase RPC kullanır.

## Güvenlik notları

- İstemci yalnızca **anon key** kullanır; satır erişimi RLS ile sınırlanır.
- Personel görünürlüğü: yalnızca kendisine atanmış talepler (müdür birimin tamamını görür).
- Tek cihaz/oturum sınırı: `active_session_token` + periyodik kontrol.

## Lisans / katkı

Bu depo staj / kurumsal geliştirme kapsamında tutulmaktadır. Değişiklikler için `main` dalına PR veya doğrudan commit politikası ekip kararına bağlıdır.
