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
- **Admin yetkisi:** Admin, herhangi bir talebi koşulsuz olarak güncelleyebilir (durum, atama dahil) — kritik durumlarda sisteme müdahale yetkisi.
- **Açan kişinin düzenleme hakkı:** Talebi açan kişi (vatandaş/personel), talep henüz kimseye atanmamışsa (`assigned_to` boşken) talebin içeriğini düzenleyebilir veya iptal edebilir. Talep atandıktan sonra bu hak kapanır.
- **Frontend gereksinimi:** Kullanıcı, zaten atanmış bir talebi düzenlemeye/iptal etmeye çalışırsa, Flutter arayüzünde şu mesajla bir uyarı gösterilmeli: "Talebiniz ilgili birim personeline atanmıştır, şu an talepte değişiklik yapılamaz." Bu kısıtlama hem RLS'te (güvenlik, zorunlu) hem frontend'de (kullanıcı deneyimi, bilgilendirici) uygulanır.

## Kimlik doğrulama (Auth)
- Kayıt ve giriş **e-posta + şifre** ile yapılır.
- Kayıt sonrası **e-posta doğrulaması** istenir (Supabase'in yerleşik e-posta doğrulaması).
- **SMS doğrulaması kullanılmaz** (ücretli servis gerektirdiği için).

## Veri modeli (tablolar)
- **departments** — birimler. Alanlar: `id`, `name`.
- **users** — kullanıcılar. Alanlar: `id`, `email`, `full_name`, `role`, `department_id`. (`role` ve `department_id` yetki mantığının temelidir. Personel ve müdür bir birime bağlıdır; vatandaşın birimi yoktur.)
- **requests** — talepler/şikâyetler. Alanlar: `id`, `title`, `description`, `category`, `status`, `requester_type`, `created_by`, `department_id`, `assigned_to`, `created_at`. (`assigned_to`, müdürün talebi atadığı personelin `id`'sidir; atanmamış talepler için `null` olabilir.)
- **attachments** — foto/video ekleri (ileride). Alanlar: `id`, `request_id`, `file_url`, `media_type`. (Dosyalar Supabase Storage'da; tabloda yalnızca adres saklanır.)
- **results** — çözüm raporları. Alanlar: `id`, `request_id`, `report_text`, `resolved_by`, `approval_status`, `approved_by`, `created_at`. (`approval_status` = `beklemede` / `onaylandi` / `reddedildi`; `resolved_by` çözen personel, `approved_by` onaylayan müdür.)
- **notifications** — bildirimler. Alanlar: `id`, `user_id`, `request_id`, `message`, `is_read`, `created_at`.

> Not: Birimlerin (departments) somut listesi henüz belirlenmedi; ileride tanımlanacaktır. Bu, kod yapısını etkilemez; yalnızca veri olarak eklenecektir.

## Talep durum akışı
`requests.status`: `acik` → `cozuldu (onay bekliyor)` → `onaylandi` (kullanıcıya iletildi) **veya** `reddedildi` (personele geri döndü, yeniden işleme alınır). Reddedilen talep tekrar çözülüp yeniden onaya sunulabilir.

- **Rapor düzenleme:** Personel, çözüm raporunu müdür onaylayana/reddedene kadar (`results.approval_status = 'beklemede'` iken) düzenleyebilir.
- **İptal:** Talebi açan kişi, talebi yalnızca henüz kimse üstlenmemişse (`status = 'acik'` **ve** `assigned_to IS NULL`) iptal edebilir.

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

**Gelecek aşama hedefi:** Bir talebin ataması (`assigned_to`) değiştiğinde (örn. admin ya da müdür tarafından yeniden atama yapıldığında), üç tarafa otomatik e-posta bildirimi gönderilmeli: eski atanmış personel, ilgili birim müdürü, yeni atanan personel. Bu, veritabanı seviyesinde bir trigger (`requests` tablosunda `assigned_to` değiştiğinde tetiklenen) ve bir Supabase Edge Function ile yapılacak (e-posta servisi API anahtarı hiçbir zaman Flutter koduna girmeyecek, Edge Function içinde gizli kalacak). MVP'de değil, RLS ve temel akış tamamlandıktan sonraki bir aşamada ele alınacak.

## RLS Planı
Aşağıdaki kurallar Supabase Row Level Security politikaları olarak tablo bazında uygulanır (nihai hâl).

> **Durum:** Bu RLS planı, Supabase Studio (Authentication > Policies) üzerinden elle, tıklanarak uygulandı ve tamamlandı. Toplam 22 politika, 5 tabloya dağıtıldı ve isim/sayı bazında doğrulandı:
> - departments: 3 politika (1 SELECT, 1 INSERT, 1 UPDATE)
> - users: 5 politika (3 SELECT, 1 INSERT, 1 UPDATE)
> - requests: 7 politika (3 SELECT, 1 INSERT, 3 UPDATE)
> - results: 4 politika (1 SELECT, 1 INSERT, 2 UPDATE)
> - notifications: 3 politika (1 SELECT, 1 INSERT, 1 UPDATE)

**departments:**
- `SELECT`: herkes (public)
- `INSERT`: sadece admin — `(select role from users where id = auth.uid()) = 'admin'`
- `UPDATE`: sadece admin — aynı koşul

**users:**
- `SELECT` (3 ayrı kural): (1) kendi profili — `id = auth.uid()`; (2) müdür kendi biriminin personelini görebilir — `department_id` eşleşmesi + rol = `mudur`; (3) admin herkesi görebilir — rol = `admin`
- `INSERT`: sadece kendi kaydını oluşturabilir — `id = auth.uid()`
- `UPDATE`: kendi profilini günceller ama rol ve `department_id` değişmemiş olmalı (`with check` ile korunur, `is not distinct from` kullanılarak null uyumluluğu sağlanır)

**requests** (7 kural):
- `SELECT` (3 kural): (1) açan kişi kendi talebini görür — `created_by = auth.uid()`; (2) personel/müdür kendi biriminin tüm taleplerini görür — `department_id` eşleşmesi + rol `in (personel, mudur)`; (3) admin hepsini görür
- `INSERT`: giriş yapmış herkes, `created_by = auth.uid()` olmalı
- `UPDATE` (3 kural): (1) müdür, kendi biriminde durum/atama günceller; (2) açan kişi, sadece `assigned_to` boşken düzenler/iptal eder; (3) admin koşulsuz günceller

**results:** `SELECT` ilgili talebi görebilen herkes; `INSERT` sadece atanan personel; `UPDATE` (içerik) atanan personel sadece `approval_status = 'beklemede'` iken; `UPDATE` (`approval_status`) sadece müdür.

**notifications:** `SELECT` sadece kendine gelen; `INSERT` sistem/trigger otomatik; `UPDATE` (okundu) sadece kendi bildirimi.

> **Optimizasyon notu:** `users`, `requests`, `results`, `notifications` tablolarında `current_user_role()` / `current_user_department()` gibi güvenli yardımcı fonksiyonlar (`security definer` ile) henüz yazılmadı — şu an doğrudan subquery kullanılıyor. Bu, ileride kısır döngü (infinite recursion) riski çıkarsa ele alınacak bir optimizasyon notu olarak düşülsün.

## Geliştirme prensipleri (Claude Code bunlara uyacak)
- **Parçalı ve modüler kod yaz.** Tek dev dosyalar oluşturma; her şeyi mantıklı klasörlere ve ayrı dosyalara böl (ekranlar, veri modelleri, servisler, Supabase bağlantısı ayrı ayrı).
- **Adım adım ilerle.** Tek seferde çok sayıda dosya üretme; görevi küçük, anlaşılır parçalara böl.
- **Her değişikliği açıkla.** Ne yaptığını ve neden yaptığını kısaca belirt (kullanıcı yeni başlayan bir geliştiricidir, öğrenmek istiyor).
- **Güvenlik önce gelir.** Özellikle RLS ve API anahtarları konusunda dikkatli ol; hassas bilgileri koda gömme.
- **Yetkilendirmeyi RLS ile yap**, uygulama katmanında değil.
- **Türkçe açıklama, standart kod.** Kod içi değişken/fonksiyon adları İngilizce standartta olabilir; açıklamalar ve kullanıcıyla iletişim Türkçe.

## Geliştirme sırası (yol haritası)
1. ✅ Git + GitHub bağlantısı
2. ✅ Flutter iskeleti + Supabase paketi
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
- **2026-07-08:** Madde 2 (Flutter iskeleti + Supabase paketi) tamamlandı olarak işaretlendi.
- **2026-07-08:** Tablo adı tickets'tan requests'e değiştirildi, RLS planı netleştirildi.
- **2026-07-09:** Git + GitHub bağlantısı tamamlandı; commit/push disiplini olarak "günde sık commit, gün sonunda birleştirip (squash) tek seferde push" yöntemi benimsendi.
- **2026-07-09:** Flutter proje iskeleti kuruldu, klasör Türkçe karakter içeren yoldan (Masaüstü) Türkçe karaktersiz bir konuma taşındı.
- **2026-07-09:** Supabase bağlantısı kuruldu: flutter_dotenv paketi eklendi, .env + .env.example ayrımı yapıldı, .gitignore'a .env eklendi, lib/services/supabase_service.dart oluşturuldu, main.dart güncellendi.
- **2026-07-09:** Veri modeli tabloları Supabase Studio (Table Editor) üzerinden elle, tıklanarak oluşturuldu: departments, users (auth.users'a foreign key ile bağlı), requests, results, notifications — hepsi ilgili foreign key bağlantılarıyla birlikte kuruldu.
- **2026-07-09:** Talep dağıtım modeli, havuzdan atama modeline değiştirildi: müdür talebi belirli bir personele atar (assigned_to), birimdeki diğer personel görebilir ama sadece atanan çözebilir.
- **2026-07-09:** departments ve users tabloları için RLS politikaları tamamlandı. requests tablosu için 7 RLS politikası (3 SELECT, 1 INSERT, 3 UPDATE) planlandı/yazıldı.
- **2026-07-09:** results ve notifications tabloları için RLS henüz yazılmadı, sıradaki adım bu.
- **2026-07-09:** Öğrenilen teknik dersler: (1) Supabase Studio'da bir sütunun default value'sunu değiştirirken "syntax error" alınırsa, en güvenilir çözüm sütunu silip yeniden oluşturmak; (2) foreign key eklenmiş bir sütunun tipini sonradan değiştirmek problemli olabiliyor, bu yüzden sütun ayarları (tip, nullable, default value) foreign key eklenmeden önce tamamlanmalı; (3) Table Editor'de birden fazla değişikliği aynı anda kaydetmeye çalışmak hatalara yol açabiliyor, her değişiklik tek tek kaydedilmeli.
- **2026-07-09:** Sıradaki adım: results ve notifications tablolarının RLS'lerini tamamlamak, sonra tüm tablo + RLS yapısını tek bir SQL migration dosyası olarak dışa aktarıp commit'lemek.
- **2026-07-09:** Tüm RLS (Row Level Security) planı tamamlandı — 5 tablo, 22 politika, Supabase Studio üzerinden elle oluşturuldu ve doğrulandı.
  - departments: herkes okur, sadece admin ekler/günceller.
  - users: kendi profili + müdür kendi birimi + admin herkes (SELECT); kendi kaydını oluşturma (INSERT); kendi profilini güncelleme, rol/department_id değişmeden (UPDATE).
  - requests: açan kişi + birim çalışanları + admin (SELECT, 3 kural); giriş yapmış herkes talep açabilir (INSERT); müdür durum/atama günceller + açan kişi henüz atanmamışsa düzenler/iptal eder + admin koşulsuz günceller (UPDATE, 3 kural).
  - results: ilgili talebi görebilen sonucu görebilir (SELECT); sadece atanan personel rapor ekler (INSERT); atanan personel beklemedeyken düzenler + müdür onaylar/reddeder (UPDATE, 2 kural).
  - notifications: kendi bildirimini görme (SELECT); sadece sistem/trigger ekleyebilir, normal kullanıcı elle ekleyemez — with check (false) (INSERT); kendi bildirimini okundu işaretleme (UPDATE).
  - Öğrenilen ek dersler: (1) bir kuralı yanlış tabloya eklemek mümkün olduğu için, tüm tablolardaki politika sayıları ve isimleri planla karşılaştırılarak tek tek doğrulandı; (2) `exists (select 1 from ... where ...)` kalıbı, bir tablonun RLS kuralının başka bir tablodaki (örn. requests) ilişkili kayda bakması gerektiğinde kullanıldı (örn. results tablosunun, bağlı olduğu request'in görülebilirlik kurallarını miras alması).
  - Sıradaki adım: Tüm tablo yapısı + RLS politikalarını tek bir SQL migration dosyası olarak dışa aktarıp git'e commit'lemek, ardından Flutter tarafında auth ekranlarına (giriş/kayıt) geçmek.
