# CLAUDE.md — TŞYS (Talep ve Şikâyet Yönetim Sistemi)

> Kullanıcıya görünen uygulama adı: **TŞYS — Talep ve Şikâyet Yönetim Sistemi**
> Kod / klasör adı: `talep_sorgu_cevap_app`

## Proje özeti
Bu, vatandaşların ve kurum personelinin arıza/talep/şikâyet girdiği bir mobil uygulamadır. Girilen her talep ilgili birime yönlendirilir; o birimin personeli tarafından çözülüp rapor yazılır; birim müdürü raporu onaylar veya reddeder. Onaylanırsa sonuç, talebi açan kişiye bildirim olarak ulaşır; reddedilirse personele geri döner ve talep yeniden ele alınır. Talepler metin içerir; ileride fotoğraf ve video ekleri de desteklenecektir.

## Teknoloji yığını
- **Frontend:** Flutter (mobil uygulama)
- **Backend / Veritabanı / Kimlik / Depolama:** Supabase (Docker üzerinde yerel, `localhost:8000`)
- **Önbellek:** Redis (ileride performans katmanı)
- **Konteynerleştirme:** Docker
- **Versiyon kontrolü:** Git + GitHub

## Roller ve yetkiler
Dört rol vardır. Yetki kuralları veritabanı seviyesinde (Supabase Row Level Security / RLS) uygulanır — Flutter tarafında `if` bloklarıyla değil.

- **Vatandaş:** Talep açar; yalnızca kendi taleplerini ve onların sonuçlarını görür.
- **Personel:** Kendi birimine kayıtlıdır. Herhangi bir birime talep açabilir (örn. İK personeli teknik birime yazıcı arızası bildirir). Kendi birimine gelen talepleri çözer ve rapor yazar. Kendi açtığı talebi kendisi de çözebilir (engellenmez; kaydı sistemde resmi olarak tutulur).
- **Birim müdürü:** Kendi birimine kayıtlıdır. İki noktada devrededir: (1) Talep birime düştüğünde, talebi **belirli bir personele atar** (`assigned_to`). (2) Atanan personelin yazdığı çözüm raporunu görür; **onaylar** veya **reddeder.** Onaylarsa sonuç, talebi açan kişiye gider. Reddederse personele "reddedildi" bildirimi düşer ve talep yeniden ele alınır.
- **Admin:** Tüm sisteme sahiptir; kullanıcı ve birim ekler/çıkarır, her şeyi görür ve yönetir.

## Talebi kim açar, kim çözer
- Talebi hem **vatandaş** hem **personel** açabilir.
- Talep, seçilen kategoriye göre ilgili birime düşer.
- **Atama modeli:** Talep birime düştüğünde, birim müdürü talebi belirli bir personele atar (`assigned_to`). Personel talebi kendi seçerek üstlenmez; atama müdür tarafından yapılır.
- **Şeffaflık:** Birimdeki diğer personel, kendine atanmamış olsa bile o talebi görebilir. Ancak yalnızca `assigned_to` alanında kendi kimliği olan personel talebi çözüp rapor yazabilir.
- Personel talepleri ile vatandaş talepleri **farklı etiketlenir** (`requester_type` = `vatandas` / `personel`). Bu, filtreleme ve raporlama içindir.

## Kimlik doğrulama (Auth)
- Kayıt ve giriş **e-posta + şifre** ile yapılır.
- Kayıt sonrası **e-posta doğrulaması** istenir (Supabase'in yerleşik e-posta doğrulaması).
- **SMS doğrulaması kullanılmaz** (ücretli servis gerektirdiği için).

## Veri modeli (tablolar)
- **departments** — birimler. Alanlar: `id`, `name`.
- **users** — kullanıcılar. Alanlar: `id`, `email`, `full_name`, `role`, `department_id`. (`role` ve `department_id` yetki mantığının temelidir. Personel ve müdür bir birime bağlıdır; vatandaşın birimi yoktur.)
- **tickets** — talepler/şikâyetler. Alanlar: `id`, `title`, `description`, `category`, `status`, `requester_type`, `created_by`, `department_id`, `assigned_to`, `created_at`. (`assigned_to`, müdürün talebi atadığı personelin `id`'sidir; atanmamış talepler için `null` olabilir.)
- **attachments** — foto/video ekleri (ileride). Alanlar: `id`, `ticket_id`, `file_url`, `media_type`. (Dosyalar Supabase Storage'da; tabloda yalnızca adres saklanır.)
- **results** — çözüm raporları. Alanlar: `id`, `ticket_id`, `report_text`, `resolved_by`, `approval_status`, `approved_by`, `created_at`. (`approval_status` = `beklemede` / `onaylandi` / `reddedildi`; `resolved_by` çözen personel, `approved_by` onaylayan müdür.)
- **notifications** — bildirimler. Alanlar: `id`, `user_id`, `ticket_id`, `message`, `is_read`, `created_at`.

> Not: Birimlerin (departments) somut listesi henüz belirlenmedi; ileride tanımlanacaktır. Bu, kod yapısını etkilemez; yalnızca veri olarak eklenecektir.

## Talep durum akışı
`tickets.status`: `acik` → `cozuldu (onay bekliyor)` → `onaylandi` (kullanıcıya iletildi) **veya** `reddedildi` (personele geri döndü, yeniden işleme alınır). Reddedilen talep tekrar çözülüp yeniden onaya sunulabilir.

## Talep oluşturma ve kategori mantığı
- Kullanıcı bir metin alanına talebini/şikâyetini yazar ve **kategoriyi kendisi seçer.**
- Seçilen kategori, talebin gideceği birimi belirler.
- **MVP'de akış sadedir:** yaz, kategori seç, gönder. Akıllı öneri/uyarı yoktur.

## Gelecek aşama hedefi — Gemini ile talep yorumlama
Çekirdek çalıştıktan sonra eklenecektir (MVP'de **değil**):
- Kullanıcının yazdığı talep metni **Google Gemini API** ile yorumlanır.
- Amaç: (a) yazılan içerik seçilen kategoriyle uyuşmuyorsa kullanıcıya uyarı göstermek (kullanıcı yine de devam edebilir; uygulama zorlamaz), ve/veya (b) içeriğe göre ilgili olabilecek birimleri öneri olarak sıralamak.
- **Güvenlik kuralı:** Gemini API anahtarı **asla Flutter uygulamasına konmaz.** Çağrı, Supabase Edge Function üzerinden yapılır; anahtar orada gizli kalır. Uygulama sadece Supabase'e "bu metni yorumla" der.
- Gemini'nin ücretsiz kotasının sınırlı olduğu göz önünde bulundurulur.

## Bildirim akışı
- Müdür bir raporu **onaylayınca:** talebi açan kişiye "talebiniz sonuçlandı" bildirimi gider.
- Müdür bir raporu **reddedince:** çözen personele "reddedildi, yeniden inceleyin" bildirimi gider.
- (Push bildirim altyapısı ileride kurulur; MVP'de uygulama içi bildirim yeterlidir.)

## Geliştirme prensipleri (Claude Code bunlara uyacak)
- **Parçalı ve modüler kod yaz.** Tek dev dosyalar oluşturma; her şeyi mantıklı klasörlere ve ayrı dosyalara böl (ekranlar, veri modelleri, servisler, Supabase bağlantısı ayrı ayrı).
- **Adım adım ilerle.** Tek seferde çok sayıda dosya üretme; görevi küçük, anlaşılır parçalara böl.
- **Her değişikliği açıkla.** Ne yaptığını ve neden yaptığını kısaca belirt (kullanıcı yeni başlayan bir geliştiricidir, öğrenmek istiyor).
- **Güvenlik önce gelir.** Özellikle RLS ve API anahtarları konusunda dikkatli ol; hassas bilgileri koda gömme.
- **Yetkilendirmeyi RLS ile yap**, uygulama katmanında değil.
- **Türkçe açıklama, standart kod.** Kod içi değişken/fonksiyon adları İngilizce standartta olabilir; açıklamalar ve kullanıcıyla iletişim Türkçe.

## Geliştirme sırası (yol haritası)
1. ✅ Git + GitHub bağlantısı
2. Flutter iskeleti + Supabase paketi
3. Kimlik doğrulama (e-posta + şifre + e-posta doğrulaması) ve roller + RLS (SELECT tüm birime açık, UPDATE yalnızca `assigned_to = kendisi` olan personele açık)
4. Çekirdek veri modeli (tablolar)
5. Çalışan çekirdek / MVP (talep aç, listele, müdür personele atar, atanan personel çözer, müdür onayı, sonuç)
6. Medya ekleri (foto/video — Supabase Storage)
7. Bildirimler (push)
8. Gemini ile talep yorumlama (gelecek aşama)
9. Performans (Redis) ve dağıtım (Docker)

## İlerleme Günlüğü
- **2026-07-08:** Proje CLAUDE.md ile başlatıldı, git ve GitHub bağlantısı kuruluyor.
- **2026-07-08:** Git deposu kuruldu, GitHub'daki (MurselAktop/talep_sorgu_cevap_app) mevcut Flutter .gitignore ile birleştirildi, ilk commit push edildi.
- **2026-07-08:** Git/GitHub push sonrası Flutter proje iskeleti kuruldu.
- **2026-07-08:** Supabase'e anon key ile bağlantı kuruldu.
- **2026-07-08:** Proje, Flutter taramasında "ü" (Türkçe karakter) kaynaklı hatalar yüzünden `OneDrive\Masaüstü\Talep_Sorgu_Cevap_App` konumundan `C:\Projeler\Talep_Sorgu_Cevap_App` konumuna taşındı.
- **2026-07-08:** Talep dağıtım modeli havuzdan atamaya değiştirildi (birim müdürü isteği üzerine).
- **2026-07-08:** `main.dart`'taki `ColorScheme.fromSeed` düzeltmesi sonrası uygulama Edge (web) hedefinde başarıyla çalıştırılıp Supabase bağlantısı doğrulandı. Windows masaüstü hedefi, makinede Visual Studio C++ build araçları eksik olduğu için şu an çalışmıyor (kodla ilgili değil, ileride giderilebilir).
