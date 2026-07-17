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
- **Personel:** Kendi birimine kayıtlıdır. Herhangi bir birime talep açabilir (örn. İK personeli teknik birime yazıcı arızası bildirir). Kendi birimine gelen talepleri çözer ve rapor yazar. Kendi açtığı talebi kendisi de çözebilir (engellenmez; kaydı sistemde resmi olarak tutulur). Personel, SADECE kendisine (`assigned_to` alanında) atanmış talepleri görebilir. Birimine gelen ama başka bir personele atanmış talepleri GÖREMEZ. (Bu, önceki "şeffaflık" kararından BİLİNÇLİ bir sapmadır, 2026-07-14 tarihinde alındı.)
- **Birim müdürü:** Kendi birimine kayıtlıdır. İki noktada devrededir: (1) Talep birime düştüğünde, talebi **belirli bir personele atar** (`assigned_to`). (2) Atanan personelin yazdığı çözüm raporunu görür; **onaylar** veya **reddeder.** Onaylarsa sonuç, talebi açan kişiye gider. Reddederse personele "reddedildi" bildirimi düşer ve talep yeniden ele alınır. Müdür, kendi biriminin TÜM taleplerini görebilir (atanmış/atanmamış fark etmeksizin) — çünkü atama yapabilmesi için önce görmesi gerekir.
- **Admin:** Tüm sisteme sahiptir; kullanıcı ve birim ekler/çıkarır, her şeyi görür ve yönetir.

- **Kayıt modeli:** Vatandaşlar kendi kendine kayıt olur — `auth.users`'a `INSERT` olduğunda tetiklenen bir veritabanı trigger'ı (`handle_new_user`), `public.users` tablosuna `role = 'vatandas'`, `department_id = null` ile otomatik profil oluşturur. Personel, müdür ve admin hesapları kendi kendine kayıt olamaz; bu hesaplar admin tarafından sonradan oluşturulur veya bir vatandaş hesabı admin tarafından yükseltilir.
  > Not: Admin'in personel/müdür rolü atama/yükseltme işlemini yapacağı arayüz henüz tasarlanmadı, MVP sonrası ele alınacak.

> **Planlanan mimari karar (2026-07-13, birim danışman hocasıyla istişare sonrası netleşti — henüz kod olarak uygulanmadı):**
> - **Vatandaş erişimi (hibrit model):** Vatandaş iki şekilde talep açabilir. (a) Hesap oluşturup (mevcut kayıt/giriş sistemiyle) giriş yaparsa, tüm geçmiş taleplerini hesabından görebilir. (b) Hesap açmak istemezse anonim olarak talep açabilir; bu durumda talebe kısa, insan tarafından okunabilir bir erişim kodu (`access_token`, 8-10 haneli, karışıklık yaratan karakterler hariç) otomatik atanır ve e-posta ile bildirilir. Vatandaş bu kodu, ayrı bir "Sonucu Sorgula" ekranından, giriş yapmadan kullanarak talebinin durumunu her zaman sorgulayabilir.
> - **Personel/Müdür/Admin kaydı (davet kodu modeli):** Kendi kendine kayıt olamazlar. Admin, panelinden belirli bir birime ve role bağlı bir davet kodu (personnel invite code) üretir ve ilgili kişiye iletir. Personel, kayıt ekranında e-posta + kendi seçtiği şifre + ad-soyad + bu davet koduyla kayıt olur; kod geçerliyse hesap, kodun tanımladığı rol/birimle oluşturulur ve kod tekrar kullanılamaz hale gelir.
>
> **Durum (2026-07-14):** Uygulandı — hem veritabanı (personnel_invites tablosu, handle_new_user() dallanması, create_request/get_request_by_token RPC'leri) hem Flutter tarafı (login/register ekranları, admin_invite_screen.dart, citizen_guest_menu_screen.dart, request_create_screen.dart, query_result_screen.dart) tamamlandı. Ayrıntılar için bkz. İlerleme Günlüğü.

## Talebi kim açar, kim çözer
- Talebi hem **vatandaş** hem **personel** açabilir.
- Talep, seçilen kategoriye göre ilgili birime düşer.
- **Atama modeli:** Talep birime düştüğünde, birim müdürü talebi belirli bir personele atar (`assigned_to`). Personel talebi kendi seçerek üstlenmez; atama müdür tarafından yapılır.
- **Görünürlük modeli (2026-07-14'te güncellendi — eski "şeffaflık" kararından kasıtlı sapma):** Personel SADECE kendisine atanmış (`assigned_to = kendisi`) talepleri görebilir, birimin geri kalanını göremez. Müdür, kendi biriminin TÜM taleplerini (atanmış/atanmamış) görebilir — atama yapabilmesi bu görünürlüğe bağlıdır. Admin her şeyi görür. Bir talebi açan kişi (vatandaş/personel), atanmış olsun olmasın, HER ZAMAN kendi açtığı talebi "Taleplerim" ekranından görebilir (bu ayrı bir kural, görünürlük modelinden etkilenmez).
- Personel talepleri ile vatandaş talepleri **farklı etiketlenir** (`requester_type` = `vatandas` / `personel`). Bu, filtreleme ve raporlama içindir.
- **Admin yetkisi:** Admin, herhangi bir talebi koşulsuz olarak güncelleyebilir (durum, atama dahil) — kritik durumlarda sisteme müdahale yetkisi.
- **Açan kişinin düzenleme hakkı:** Talebi açan kişi (vatandaş/personel), talep henüz kimseye atanmamışsa (`assigned_to` boşken) talebin içeriğini düzenleyebilir veya iptal edebilir. Talep atandıktan sonra bu hak kapanır.
- **Frontend gereksinimi:** Kullanıcı, zaten atanmış bir talebi düzenlemeye/iptal etmeye çalışırsa, Flutter arayüzünde şu mesajla bir uyarı gösterilmeli: "Talebiniz ilgili birim personeline atanmıştır, şu an talepte değişiklik yapılamaz." Bu kısıtlama hem RLS'te (güvenlik, zorunlu) hem frontend'de (kullanıcı deneyimi, bilgilendirici) uygulanır.

## Kimlik doğrulama (Auth)
- Kayıt ve giriş **e-posta + şifre** ile yapılır.
- Kayıt sonrası **e-posta doğrulaması** istenir (Supabase'in yerleşik e-posta doğrulaması).
- **SMS doğrulaması kullanılmaz** (ücretli servis gerektirdiği için).

> **Planlanan mimari karar (2026-07-13, henüz uygulanmadı):** Login ekranı "Vatandaş Girişi" / "Personel Girişi" olarak iki ayrı giriş noktası sunacak. İkisi de aynı tek Supabase backend'ine bağlanır (ayrı sunucu yok); giriş başarılı olduktan sonra Flutter, dönen kullanıcının rolünü seçilen giriş noktasıyla karşılaştırır — uyuşmazsa oturumu kapatıp "Bu giriş sadece personel/vatandaş için" gibi bir hata gösterir. Personel Girişi ekranında "Kayıt Ol" bağlantısı, davet kodu isteyen personel kayıt ekranına gider.
>
> **Durum (2026-07-14):** Uygulandı — bkz. `lib/screens/login_screen.dart` ve İlerleme Günlüğü. Ayrıca giriş yapmadan devam edip anonim talep açabilme / kod ile sorgulama seçeneği de (`citizen_guest_menu_screen.dart`) eklendi.

## Veri modeli (tablolar)
- **departments** — birimler. Alanlar: `id`, `name`.
- **users** — kullanıcılar. Alanlar: `id`, `email`, `full_name`, `role`, `department_id`. (`role` ve `department_id` yetki mantığının temelidir. Personel ve müdür bir birime bağlıdır; vatandaşın birimi yoktur.)
- **requests** — talepler/şikâyetler. Alanlar: `id`, `title`, `description`, `category`, `status`, `requester_type`, `created_by`, `department_id`, `assigned_to`, `access_token`, `created_at`. (`assigned_to`, müdürün talebi atadığı personelin `id`'sidir; atanmamış talepler için `null` olabilir. `created_by` anonim talepler için `null` olabilir. `access_token`, `generate_access_token()` ile otomatik üretilen, anonim sorgulama için kullanılan kısa/okunabilir koddur.)
- **attachments** — foto/video ekleri (ileride). Alanlar: `id`, `request_id`, `file_url`, `media_type`. (Dosyalar Supabase Storage'da; tabloda yalnızca adres saklanır.)
- **results** — çözüm raporları. Alanlar: `id`, `request_id`, `report_text`, `resolved_by`, `approval_status`, `approved_by`, `created_at`. (`approval_status` = `beklemede` / `onaylandi` / `reddedildi`; `resolved_by` çözen personel, `approved_by` onaylayan müdür.)
- **notifications** — bildirimler. Alanlar: `id`, `user_id`, `request_id`, `message`, `is_read`, `created_at`.
- **personnel_invites** — personel/müdür/admin davet kodları. Alanlar: `id`, `code`, `department_id`, `role`, `created_by`, `used`, `used_by`, `used_at`, `created_at`. (`code`, `generate_invite_code()` ile otomatik üretilir; kod kullanılınca `used = true` olur ve tekrar kullanılamaz. FK davranışları için bkz. aşağıdaki "personnel_invites Foreign Key Kararları" bölümü.)

> Not: Birimlerin (departments) somut listesi henüz belirlenmedi; ileride tanımlanacaktır. Bu, kod yapısını etkilemez; yalnızca veri olarak eklenecektir.

> **Planlanan şema değişiklikleri (2026-07-13, henüz uygulanmadı):**
> - `requests.created_by` alanı nullable olacak (anonim talepler için).
> - `requests` tablosuna yeni bir `access_token` sütunu eklenecek (anonim sorgulama için, kısa/okunabilir kod).
> - Yeni bir `personnel_invites` tablosu eklenecek (kod, hedef birim, hedef rol, kullanıldı mı, kimin oluşturduğu).
>
> **Durum (2026-07-14):** Uygulandı — üç madde de veritabanında tamamlandı (yukarıdaki tablo listesine yansıtıldı). Ayrıca `requests.requester_type` için `in ('vatandas', 'anonim', 'personel')` CHECK constraint'i eklendi.

## personnel_invites Foreign Key Kararları (ON DELETE davranışları)

- department_id → departments.id : ON DELETE CASCADE
  (Birim silinirse, o birime ait kullanılmamış/kullanılmış davet kodları da silinir. Sebep: kodun tek işlevi "şu birime personel ata" demek, birim yoksa kodun sistemde durmasının anlamı yok.)

- created_by → users.id (admin) : ON DELETE SET NULL
  (Admin hesabı silinirse, oluşturduğu davet kodları silinmez, sadece "kim oluşturdu" bilgisi NULL olur. Kodun işlevselliği bundan etkilenmez.)

- used_by → users.id (personel) : ON DELETE SET NULL
  (Personel hesabı silinirse, kullandığı davet kodu kaydı silinmez, sadece "kim kullandı" bilgisi NULL olur. Böylece "kaç kod üretildi, kaçı kullanıldı" gibi istatistikler bozulmaz.)

## Gelecekte Değerlendirilebilir: Soft Delete Deseni

Şu an users tablosunda bir kullanıcı silindiğinde satır fiziksel olarak veritabanından kalkıyor (hard delete). İleride, kurumsal bir yaklaşım olarak users tablosuna is_active (boolean) veya deleted_at (timestamp, nullable) sütunu eklenip "silme" işleminin aslında bu alanı güncellemek olması (soft delete) değerlendirilebilir. Bu sayede personel/admin hesapları hiçbir zaman fiziksel olarak silinmez, geçmiş kayıtlar (davet kodları, talepler, sonuçlar) hep tutarlı kalır. Bu, MVP kapsamının dışında, ileride ele alınacak bir iyileştirme notu olarak buraya eklendi, şu an için herhangi bir kod değişikliği gerektirmiyor.

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

**requests** (8 kural):
- `SELECT` (4 kural, 2026-07-14'te güncellendi): (1) açan kişi kendi talebini görür — `created_by = auth.uid()` (`acan_kisi_kendi_talebini_gorebilir`); (2) müdür kendi biriminin TÜM taleplerini görür — `department_id` eşleşmesi + rol = `mudur` (`mudur_biriminin_tum_taleplerini_gorebilir`); (3) personel SADECE kendisine atanan talepleri görür — `assigned_to = auth.uid()` + rol = `personel` (`personel_atanan_talepleri_gorebilir`); (4) admin hepsini görür (`admin_tum_talepleri_gorebilir`). Not: personel artık biriminin tüm taleplerini göremez, bu eski "şeffaflık" planından bilinçli bir sapmadır.
- `INSERT`: giriş yapmış herkes, `created_by = auth.uid()` olmalı
- `UPDATE` (3 kural): (1) müdür, kendi biriminde durum/atama günceller; (2) açan kişi, sadece `assigned_to` boşken düzenler/iptal eder; (3) admin koşulsuz günceller

**results:** `SELECT` ilgili talebi görebilen herkes; `INSERT` sadece atanan personel; `UPDATE` (içerik) atanan personel sadece `approval_status = 'beklemede'` iken; `UPDATE` (`approval_status`) sadece müdür.

**notifications:** `SELECT` sadece kendine gelen; `INSERT` sistem/trigger otomatik; `UPDATE` (okundu) sadece kendi bildirimi.

> **Güncelleme (2026-07-10):** `users` tablosunda kendi kendine subquery yapan politikalar "infinite recursion detected in policy for relation users" (kod 42P17) hatası verdi. Çözüm olarak `current_user_role()` ve `current_user_department()` adında iki `security definer` fonksiyon oluşturuldu (RLS'i by-pass ederek `users` tablosunu okuyorlar, böylece döngü kırılıyor). `users`, `requests`, `results` tablolarındaki ilgili tüm politikalar (`(select role from users where id = auth.uid())` / `(select department_id from users where id = auth.uid())` kalıbı geçenler) bu fonksiyonları kullanacak şekilde yeniden yazıldı. `notifications` tablosunda bu kalıp hiç kullanılmadığı için dokunulmadı.

> **Güncelleme (2026-07-14):** Hibrit vatandaş erişimi ve davet kodu modeli için RLS genişletildi: (1) `personnel_invites` tablosuna admin-only 4 politika eklendi (`current_user_role() = 'admin'` ile SELECT/INSERT/UPDATE/DELETE); (2) `requests` tablosuna, `anon` rolü için ayrı bir `INSERT` politikası eklendi (`to anon with check (created_by is null)`) — böylece anonim kullanıcılar da (giriş yapmadan) talep açabiliyor. `create_request` ve `get_request_by_token` RPC fonksiyonları `security definer` olarak yazıldığı için PostgREST'in `.insert().select()` ikili SELECT+INSERT RLS gereksinimini RLS politikası eklemeden aşıyor; bu iki fonksiyon kendi içlerinde `auth.uid()` doğrulaması yapıyor.

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
3. ✅ Kimlik doğrulama (e-posta + şifre + e-posta doğrulaması) ve roller + RLS (SELECT tüm birime açık, UPDATE yalnızca `assigned_to = kendisi` olan personele açık)
4. ✅ Çekirdek veri modeli (tablolar)
5. ✅ Çalışan çekirdek / MVP (talep aç, listele, müdür personele atar, atanan personel çözer, müdür onayı, sonuç) — tüm alt adımlar tamamlandı, bkz. MVP tamamlanma kontrol listesi

## MVP tamamlanma kontrol listesi (madde 5'in alt adımları)
- [x] Talep oluşturma (vatandaş/anonim/personel, create_request RPC)
- [x] Talep listeleme (Gelen Talepler: müdür biriminin tümü, personel sadece atananı; Taleplerim: herkes kendi oluşturduğu; anonim/vatandaş için access_token ile sorgulama)
- [x] Talep detay ekranı
- [x] Talep düzenleme/iptal (açan kişi, SADECE assigned_to boşken; atanmışsa "Talebiniz ilgili birim personeline atanmıştır, şu an talepte değişiklik yapılamaz." uyarısı gösterilmeli)
- [x] Talep atama ekranı (müdür → personel, assigned_to güncellemesi)
- [x] Talep çözümleme ekranı (atanan personel, results tablosuna rapor yazma)
- [x] Onay ekranı (müdür onay/red, red durumunda personele geri dönüş akışı)
- [x] Basit uygulama içi bildirim ekranı (notifications tablosu zaten var, Flutter tarafı yok — CLAUDE.md'nin kendi tanımına göre MVP'de push değil ama in-app bildirim gerekli)

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
- **2026-07-10:** Swagger UI, Docker üzerinde kuruldu ve üç teknik engel (apikey'siz şema erişimi, yanlış host adresi, eksik securityDefinitions) sırayla çözülerek tam çalışır hale getirildi.
- **2026-07-10:** users tablosunda kritik bir RLS hatası (infinite recursion, kod 42P17) tespit edildi ve current_user_role()/current_user_department() adlı security definer fonksiyonlarıyla çözüldü.
- **2026-07-10:** Tüm 5 tablo (departments, users, requests, results, notifications) hem terminal (curl) hem Swagger UI üzerinden GET istekleriyle test edildi — hepsi 200 ve boş liste [] döndürdü, RLS'in gerçekten çalıştığı doğrulandı.
- **2026-07-10:** Sıradaki adım: Migration dosyasını çıkarıp commit'lemek, ardından Flutter auth ekranlarına geçmek.
- **2026-07-10:** Kullanıcı kaydı (signUp) ile public.users profili arasındaki senkronizasyon için trigger tabanlı yöntem uygulandı: handle_new_user() adlı security definer fonksiyonu ve auth.users üzerinde after insert tetiklenen on_auth_user_created trigger'ı oluşturuldu. Fonksiyon, raw_user_meta_data içindeki full_name'i okuyup public.users'a role='vatandas', department_id=null ile otomatik satır ekliyor.
  - Kurulum pg_proc (prosecdef = true) ve pg_trigger sorgularıyla doğrulandı — fonksiyon ve trigger veritabanında gerçekten mevcut.
  - Henüz yapılmadı / sıradaki adım: gerçek bir signUp isteğiyle uçtan uca test (auth.users + public.users'a doğru yazılıyor mu doğrulamak). Bu test tamamlanınca migration dosyası çıkarılıp commit'lenecek, ardından MVP akışına geçilecek.
- **2026-07-13:** signUp testinde SMTP servisi tanımlı olmadığı için e-posta doğrulama maili gönderimi başarısız oluyor ve tüm kayıt 500 hatasıyla rollback ediliyor. Yerel geliştirmede GOTRUE_MAILER_AUTOCONFIRM=true ile e-posta doğrulaması geçici olarak devre dışı bırakıldı (SMTP servisi henüz bağlı değil). Production'a geçmeden önce gerçek bir SMTP servisi bağlanıp bu ayar kapatılmalı.
  - Not: Ayar, ana Supabase compose dosyasında (`C:\Users\makto\supabase\docker\docker-compose.yml`, bu repo dışında) zaten `${ENABLE_EMAIL_AUTOCONFIRM}` değişkenine bağlıydı; asıl değişiklik aynı klasördeki `.env` dosyasında `ENABLE_EMAIL_AUTOCONFIRM=false` → `true` yapmak oldu, ardından `docker compose up -d auth` ile auth servisi yeniden oluşturuldu.
- **2026-07-13:** Kullanıcı kaydı (signUp) uçtan uca gerçek bir istekle test edildi ve başarıyla doğrulandı: Swagger UI üzerinden atılan bir signup isteği 200 döndü, auth.users'a kayıt düştü, handle_new_user() trigger'ı çalışıp public.users'a otomatik profil (role='vatandas', department_id=null, full_name doğru) oluşturdu. Bu, projenin en kritik akışlarından birinin (kimlik doğrulama ↔ profil senkronizasyonu) uçtan uca çalıştığının kanıtı oldu.
  - Test sırasında iki ayrı sorun tespit edilip çözüldü: (1) yerel Docker kurulumunda SMTP servisi tanımlı olmadığı için kayıt sonrası e-posta doğrulama gönderimi başarısız oluyor ve tüm kaydı geri alıyordu (rollback, HTTP 500); GOTRUE_MAILER_AUTOCONFIRM=true ayarıyla yerel test için e-posta doğrulaması geçici olarak devre dışı bırakıldı, kullanıcılar artık otomatik onaylanıyor (email_confirmed_at anında dolduruluyor). (2) Swagger UI'a, REST API şemasının yanına ikinci bir şema (swagger/auth-openapi.json) eklenerek Auth API (signup, token) endpoint'leri de görsel olarak test edilebilir hale getirildi.
  - ÖNEMLİ NOT: GOTRUE_MAILER_AUTOCONFIRM=true sadece yerel geliştirme içindir. Production'a geçmeden önce gerçek bir SMTP servisi bağlanıp bu ayar kapatılmalı, aksi halde gerçek kullanıcılar e-posta doğrulaması yapmadan hesap açabilir.
  - Auth akışının uçtan uca çalıştığı doğrulandığı için, ertelenen migration dosyasının çıkarılması artık bir sonraki adım olarak netleşti.
- **2026-07-13:** Flutter tarafında giriş (login) ve kayıt (register) ekranları oluşturuldu; AuthGate ile uygulama açılışında oturum kontrolü yapılıp kullanıcı ilgili ekrana yönlendiriliyor.
  - Kayıt sonrası bilinçli olarak signOut() çağrılıyor (GOTRUE_MAILER_AUTOCONFIRM açık olduğu için signUp otomatik oturum açtırıyor, kullanıcı yine de login ekranına yönlendiriliyor).
  - Ad-soyad alanındaki bir doğrulama açığı (sadece boşluk karakteri geçerli sayılıyordu) düzeltildi.
  - Tüm akış gerçek Flutter arayüzünden uçtan uca test edildi: kayıt, login ekranına yönlendirme, yanlış şifre hata mesajı, doğru şifreyle giriş ve ana ekrana ulaşma — hepsi başarılı.
  - Migration dosyası daha önce push edildi. Sıradaki adım: talep oluşturma ve listeleme ekranları (MVP'nin çekirdek akışı).
- **2026-07-13:** Birim danışman hocasıyla istişare sonrası, vatandaş erişimi için hibrit model (hesaplı + anonim kod ile sorgulama) ve personel kaydı için davet kodu tabanlı model tasarım kararı olarak netleşti. Henüz kod olarak uygulanmadı, sıradaki adım olarak planlandı.
- **2026-07-13:** handle_new_user() trigger'ı, kayıt sırasında invite_code gönderilip gönderilmediğine göre dallanacak şekilde güncellendi: kod varsa personnel_invites tablosundan role/department_id okunup personel profili oluşturuluyor ve kod "kullanıldı" işaretleniyor; kod yoksa eskisi gibi vatandaş profili oluşturuluyor. Dört senaryo (geçerli kod, tekrar kullanım reddi, kodsuz kayıt, veritabanı doğrulamaları) Swagger UI üzerinden test edilip doğrulandı.
- **2026-07-13:** Admin davet kodu oluşturma ekranı (admin_invite_screen.dart), personel kayıt ekranı (personnel_register_screen.dart) ve giriş ekranının Vatandaş Girişi/Personel Girişi olarak ikiye ayrılması + giriş sonrası rol doğrulaması (login_screen.dart) tamamlandı. Uçtan uca test edildi: admin daveti oluşturma, o davetle personel kaydı, doğru/yanlış giriş türü senaryoları, rol uyuşmazlığında otomatik çıkış ve Türkçe hata mesajı — hepsi doğrulandı.
- **2026-07-14:** Hibrit vatandaş erişimi (hesaplı + anonim erişim kodu) ve davet kodu tabanlı personel kaydı mimarisinin veritabanı tarafı tamamlandı:
  - `personnel_invites` tablosu oluşturuldu: `code` (unique, `generate_invite_code()` ile otomatik üretilir), `department_id` (departments'a FK, `on delete cascade`), `role`, `created_by`/`used_by` (users'a FK, `on delete set null`, nullable), `used` (boolean), `created_at`, `used_at`. FK kararlarının gerekçeleri "personnel_invites Foreign Key Kararları" bölümüne eklendi.
  - `generate_invite_code()` ve `generate_access_token()` fonksiyonları eklendi (karışıklık yaratan karakterler hariç rastgele, insan tarafından okunabilir kod üretimi).
  - `personnel_invites` üzerinde admin-only RLS politikaları uygulandı (`current_user_role() = 'admin'` kontrolüyle SELECT/INSERT/UPDATE/DELETE).
  - `requests` tablosuna `access_token` sütunu eklendi (text, NOT NULL, unique, default `generate_access_token()`); `created_by` nullable yapıldı (anonim talepler için); `requester_type` için `in ('vatandas', 'anonim', 'personel')` CHECK constraint eklendi.
  - `handle_new_user()` trigger fonksiyonu, kayıt sırasında `invite_code` gönderilip gönderilmediğine göre dallanacak şekilde yeniden yazıldı: kod varsa `personnel_invites`'tan `for update` ile satır kilitlenip role/department_id okunuyor ve personel kaydı yapılıyor (kod geçersiz/kullanılmışsa `raise exception` ile tüm kayıt reddediliyor), kod yoksa eskisi gibi `role = 'vatandas'` ile kayıt yapılıyor.
  - `requests` tablosuna anonim `INSERT` için ek bir RLS politikası eklendi (`to anon with check (created_by is null)`).
  - `create_request(p_title, p_description, p_category, p_department_id, p_requester_type, p_created_by)` adında `security definer` bir RPC fonksiyonu yazıldı; `auth.uid()` ile `p_created_by`/`p_requester_type` doğrulaması yaparak kimlik sahteciliğini engelliyor, talebi ekleyip `access_token`'ı döndürüyor. Bu, PostgREST'in `.insert().select()` ikili SELECT+INSERT RLS gereksinimini aşmak için `security definer` deseni kullanılarak çözüldü.
  - `get_request_by_token(p_access_token)` adında `security definer` bir RPC fonksiyonu yazıldı; `requests`+`departments` join edip title/description/category/status/created_at/department_name döndürüyor. Güvenlik sertleştirmesi olarak `requester_type in ('vatandas','anonim')` filtresi eklendi — personel taleplerinin token ile sorgulanamamasını garanti ediyor.
- **2026-07-14:** Aynı mimarinin Flutter tarafı tamamlandı:
  - `lib/screens/login_screen.dart` yeniden yazıldı: Vatandaş Girişi / Personel Girişi / Giriş Yapmadan Devam Et seçim ekranı, paylaşılan form widget'ı, giriş sonrası `public.users.role` kontrolü (uyuşmazsa otomatik `signOut` + Türkçe hata).
  - `lib/screens/register_screen.dart` ve `lib/screens/personnel_register_screen.dart`'a inline hata mesajları eklendi (zaten kayıtlı e-posta, geçersiz/kullanılmış davet kodu — artık genel SnackBar yerine ilgili `TextFormField`'ın altında gösteriliyor).
  - `lib/screens/admin_invite_screen.dart` (yeni) — admin'in birim+rol seçip davet kodu ürettiği, kopyalanabilir kod gösteren ve geçmiş davetleri listeleyen ekran.
  - `lib/screens/citizen_guest_menu_screen.dart` (yeni) — "Talep Oluştur" ve "Sonucu Sorgula" menüsü.
  - `lib/screens/request_create_screen.dart` (yeni) — talep formu; `requester_type`/`created_by` giriş durumuna göre otomatik belirleniyor (giriş yoksa anonim, vatandaşsa vatandas, personelse personel); `create_request` RPC'sini çağırıp dönen `access_token`'ı kullanıcıya kopyalanabilir şekilde gösteriyor.
  - `lib/screens/query_result_screen.dart` (yeni) — talep kodu girip `get_request_by_token` RPC'sini çağıran, sonucu Türkçe etiketlerle (durum, kategori vb.) gösteren ekran.
  - `lib/screens/home_screen.dart`, `StatefulWidget`'a çevrilip giriş yapmış herhangi bir kullanıcı (vatandaş VEYA personel) için "Talep Oluştur" butonu gösterilecek şekilde düzeltildi (personelin de kurum-içi arıza/talep açabilmesi gerektiği için).
- **2026-07-14:** Hibrit vatandaş erişim mimarisi tamamlandı: personnel_invites tablosu + davet kodu üretimi (generate_invite_code), requests.access_token (generate_access_token) ile anonim/vatandaş sorgu takibi, requests.requester_type (vatandas/anonim/personel) ayrımı, handle_new_user() trigger'ının davet koduna göre dallanması.
- **2026-07-14:** Anonim talep oluşturma sorunu (PostgREST'in insert+select ikili RLS gereksinimi) create_request() security definer RPC fonksiyonuyla çözüldü; kimlik sahteciliğine karşı auth.uid() doğrulamasıyla sertleştirildi.
- **2026-07-14:** get_request_by_token() RPC'si, requester_type filtresiyle sertleştirildi — personel talepleri artık anonim token sorgusuyla asla görüntülenemiyor.
- **2026-07-14:** Flutter tarafında tamamlanan ekranlar: login_screen (vatandaş/personel/misafir girişi ayrımı), register_screen ve personnel_register_screen (inline hata mesajları), admin_invite_screen (davet kodu üretimi ve geçmişi), citizen_guest_menu_screen, request_create_screen, query_result_screen, request_list_screen (Gelen Talepler), my_requests_screen (Taleplerim), home_screen (rol bazlı buton görünürlüğü, Çıkış Yap butonu).
- **2026-07-14:** Güvenlik sertleştirmesi: login_screen'deki rol uyuşmazlığı hata mesajı, hesabın var olup olmadığını/rolünü sızdırmaması için genel bir mesaja indirgendi (register_screen'deki e-posta sızıntısı dersiyle aynı prensip).
- **2026-07-14:** Önemli mimari ders: RLS bir kullanıcının görebileceği ÜST SINIRI belirler, hangi EKRANIN o sorguyu attığını bilmez. Aynı sorguyu (ek filtresiz) atan iki farklı ekran, aynı kullanıcı için her zaman aynı (RLS'in izin verdiği tam) sonucu döndürür. Bir ekranın RLS'in izin verdiği kümenin sadece bir ALT KÜMESİNİ göstermesi gerekiyorsa (örn. "Taleplerim" sadece kendi oluşturduklarını, "Gelen Talepler" sadece atananı/birimi göstermeli), istemci tarafında ek WHERE filtresi (örn. .eq('created_by', ...) veya .eq('assigned_to', ...)) yazılması ŞART — RLS'e güvenmek tek başına yeterli değil.
- **2026-07-14:** CLAUDE.md'deki "Şeffaflık" kararından (personel biriminin tüm taleplerini görür) bilinçli olarak sapıldı: personel artık SADECE kendisine atanan talepleri görüyor (assigned_to = auth.uid()), müdür ise atama yapabilmek için biriminin tüm taleplerini görmeye devam ediyor. RLS, "birim_personeli_kendi_talepleri_gorebilir" kuralı kaldırılıp mudur_biriminin_tum_taleplerini_gorebilir / personel_atanan_talepleri_gorebilir / admin_tum_talepleri_gorebilir olarak üçe bölünerek güncellendi.
- **2026-07-14:** Bilinen eksikler / sıradaki adımlar: talep detay ekranı, talep atama ekranı (müdür → personel, assigned_to güncellemesi), talep çözümleme ekranı (results tablosu), onay ekranı (müdür onay/red); migration dosyasının güncellenmesi; GOTRUE_MAILER_AUTOCONFIRM'in production öncesi kapatılması; git commit+push'un yapılması; get_request_by_token'daki not_found/forbidden mesaj ayrımının bilinçli olarak ertelenmesi.
- **2026-07-14:** requests tablosu için görünürlük modeli değiştirildi: birim_personeli_kendi_talepleri_gorebilir kuralı kaldırılıp, mudur_biriminin_tum_taleplerini_gorebilir (müdür → biriminin tüm talepleri) ve personel_atanan_talepleri_gorebilir (personel → SADECE assigned_to = kendisi) olarak ikiye ayrıldı; admin_tum_talepleri_gorebilir ayrı bir kural olarak eklendi. Bu, CLAUDE.md'deki eski "şeffaflık" kararından bilinçli bir sapmadır.
- **2026-07-14:** Test sürecinde önemli bir teşhis vakası yaşandı: müdür test hesabı (mudur1.test@test.com) davet kodu sorunuyla sessizce oluşturulamamıştı (trigger'ın raise exception ile tüm kaydı geri alması); test sırasında bu fark edilmeden hâlâ admin oturumuyla test yapılmış, bu da "müdürün her iki birimi de gördüğü" yanlış izlenimini verdi. SQL ile auth.users + public.users join sorgusuyla hesabın hiç var olmadığı doğrulandı, hesap dikkatlice yeniden oluşturularak çözüldü. Genel ders: bir test beklenmedik sonuç verdiğinde, önce "gerçekten doğru hesapla mı test ediyorum" diye kontrol etmek gerekir.
- **2026-07-14:** MVP'nin kalan adımları netleştirildi ve önceliklendirildi: (A) birbirine bağımlı, teker teker yapılacak ekranlar — talep detay, düzenleme/iptal, atama, çözümleme, onay, bildirim; (B) bağımsız, A bittikten sonra yapılacak işler — migration dosyası güncelleme, GOTRUE_MAILER_AUTOCONFIRM kapatma (production öncesi), git commit+push. A grubunun tek seferde değil, önceki adımlarda olduğu gibi teker teker ve her birinin ayrı test edilmesi kararlaştırıldı (RLS-istemci filtresi ayrımı ve müdür kaydı vakalarında küçük adımların hataları yakalamadaki değeri kanıtlandığı için).
- **2026-07-16:** MVP'nin çekirdek fonksiyonel döngüsü tamamlandı: talep oluşturma → listeleme/sorgulama → detay görüntüleme → atama (müdür→personel) → çözümleme (personel raporu) → onay/red (müdür) → red sonrası yeniden düzenleyip gönderme → bildirim (onay/red anında ilgili kişiye uygulama içi bildirim) tüm akış uçtan uca test edildi ve doğrulandı. Ayrıca: results.previously_rejected sütunu + trigger'ı ile "bu rapor daha önce reddedilmişti" bilgisi kalıcı olarak işaretleniyor; requests.status için CHECK kısıtlaması olmadığı için 'iptal' durumu eklendi. Sıradaki adım: migration dosyasının güncellenmesi, GOTRUE_MAILER_AUTOCONFIRM ayarının gözden geçirilmesi, git commit+push.
- **2026-07-16:** A grubu (MVP çekirdek fonksiyonel döngüsü — talep detay, düzenleme/iptal, atama, çözümleme, onay, bildirim ekranları) resmi olarak tamamlandı kabul edildi; roadmap madde 5 ve MVP tamamlanma kontrol listesindeki 8 madde de zaten ✅. `supabase db diff --schema public` ile şema kontrolü yapıldı: "No schema changes found" — A grubu geliştirmesi sırasında (previously_rejected sütunu, sync trigger'ları dahil) şemada zaten önceki migration'a yansıtılmamış hiçbir fark kalmadığı doğrulandı, yeni migration dosyası oluşturulmadı. GOTRUE_MAILER_AUTOCONFIRM notu ayrı bir "Yapılacaklar / Production Öncesi Kontrol Listesi" bölümüne taşındı. Sıradaki adım: B grubu — Medya ekleri (foto/video, roadmap madde 6) veya push bildirimler (madde 7).
- **2026-07-16:** Android mobil hedefi için sağlık kontrolü yapıldı: `flutter doctor -v` Android toolchain'i geçerli gösterdi (Android SDK 36.1.0, tüm lisanslar kabul edilmiş). Android Studio Device Manager üzerinden **Pixel 8** emülatörü oluşturuldu (`flutter emulators` listesinde görünüyor). `flutter run -d Pixel_8` ile uygulama emülatörde başlatıldı ve ekranda göründü; ancak konsolda hata/uyarı olup olmadığı net doğrulanmadı. Bu sadece bir **açılış/sağlık kontrolüdür** — giriş, talep oluşturma gibi hiçbir akış bu adımda elle test edilmedi (2026-07-08 tarihli kayıtta belirtilen "Windows masaüstü hedefi çalışmıyor" sorununa karşı Android'in canlı bir mobil test hedefi olarak kullanılabilir olduğunu doğrular). Sıradaki adım: uygulamanın Android emülatöründe temel akışlarla (giriş, talep oluşturma vb.) fiilen manuel test edilmesi.
- **2026-07-17:** Android emülatör sağlık kontrolü tamamlandı, MVP'nin tüm çekirdek akışları gerçek platformda doğrulandı: vatandaş talep oluşturma, müdür atama, personel çözümleme, müdür onay/red, bildirim — hepsi emülatörde uçtan uca başarıyla test edildi.

## Yapılacaklar / Production Öncesi Kontrol Listesi
- [ ] `GOTRUE_MAILER_AUTOCONFIRM=true` (docker-compose.yml / ilgili `.env`) sadece YEREL GELİŞTİRME ayarıdır — e-posta doğrulaması olmadan hesapları otomatik onaylıyor. Production'a geçmeden önce gerçek bir SMTP servisi bağlanıp bu ayar `false` yapılmalı; aksi halde gerçek kullanıcılar e-posta doğrulaması yapmadan hesap açabilir (bkz. 2026-07-13 tarihli İlerleme Günlüğü kayıtları). **Durum (2026-07-16): henüz değiştirilmedi, sadece kayıt altına alındı.**
- [ ] Ek (attachment) silme özelliği MVP'de yok, ileride eklenebilir (2026-07-17: `attachments` tablosu/bucket için bilinçli olarak DELETE RLS politikası yazılmadı — admin dahil hiç kimse şu an bir eki silemiyor).
- [ ] Anonim (access_token ile takip edilen) taleplerde medya eki görüntüleme/yükleme şu an desteklenmiyor — `created_by` null olduğu için RLS eşleşmiyor; ileride token bazlı ayrı bir erişim yolu tasarlanmalı.

## Bilinen Ortam Notları
- **Android emülatöründe fiziksel klavye Türkçe karakter sorunu (2026-07-17):** Windows host klavyesinden emülatöre Türkçe karakterler (ş, ı, ğ vb.) doğru iletilmiyor. Bu bir uygulama/kod hatası DEĞİL, saf bir emülatör/host fiziksel klavye eşleme sorunu — doğrulandı çünkü emülatörün kendi dokunmatik ekran klavyesine geçilince Türkçe karakterler sorunsuz giriliyor. **Çözüm:** Emülatörde Türkçe karakter girilmesi gereken testlerde fiziksel klavye yerine emülatörün dokunmatik ekran klavyesini kullanın.

## Bilinen Eksikler / Sonraki Adımlar
- `get_request_by_token` fonksiyonunda "kayıt bulunamadı" ile "yetkisiz erişim" (`requester_type = 'personel'` olan bir talebe token ile erişilmeye çalışılması) durumlarını ayrı mesajlarla ayırt etme fikri bilinçli olarak ertelendi. Güvenlik zaten sağlanmış durumda (fonksiyon her iki durumda da boş liste döndürüyor, personel taleplerine token ile erişim mümkün değil); bu yalnızca bir UX inceliği, ileride ele alınabilir.
