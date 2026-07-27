-- =====================================================================
-- TŞYS — Cloud test verisi tohumlama (seed) betiği (2026-07-26)
-- =====================================================================
-- Amaç: Supabase Cloud veritabanına, MEVCUT gerçek veriye (kullanıcının
-- kendi admin hesabı, gerçek birimler/talepler) hiç dokunmadan, üzerine
-- ek olarak gerçekçi test verisi eklemek.
--
-- Tasarım kararı: Veriler doğrudan INSERT ile değil, mevcut trigger
-- zincirinden (handle_new_user, log_request_created, log_request_assigned,
-- sync_request_status_from_result, log_result_resolved, log_result_updated)
-- GEÇİRİLEREK ekleniyor — böylece request_history, notifications,
-- resolved_at gibi türetilmiş alanlar gerçek uygulama akışıyla birebir
-- aynı şekilde, elle taklit edilmeden oluşuyor.
--
-- Kapsam DIŞI (bilinçli): gerçek dosya içermediği için attachments
-- (medya ekleri) eklenmedi — sahte/boş dosya kaydı yanıltıcı olurdu.
--
-- Şifre: tüm test hesapları için "Test1234!" (bcrypt ile hashlenir).
-- E-posta deseni: seed.*@tsys.local — gerektiğinde bu betiğin eklediği
-- verinin kolayca ayırt edilip temizlenebilmesi için.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0) Geçici referans tabloları: her satıra insan-okunabilir bir etiket
--    verip UUID'leri bu etiketle çağırıyoruz — sonraki adımlarda RETURNING/
--    \gset gerekmeden aynı kullanıcıya/talebe tekrar tekrar atıfta
--    bulunabiliyoruz.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE seed_ids (
    label text PRIMARY KEY,
    id uuid DEFAULT gen_random_uuid()
) ON COMMIT DROP;

INSERT INTO seed_ids (label) VALUES
    ('admin_2'),
    ('mudur_100'), ('mudur_101'), ('mudur_102'), ('mudur_103'), ('mudur_104'),
    ('per_100a'), ('per_100b'), ('per_101a'), ('per_101b'),
    ('per_102a'), ('per_102b'), ('per_103a'), ('per_103b'),
    ('per_104a'), ('per_104b'),
    ('vat_1'), ('vat_2'), ('vat_3'), ('vat_4');

CREATE TEMP TABLE req_ids (
    label text PRIMARY KEY,
    id uuid DEFAULT gen_random_uuid()
) ON COMMIT DROP;

INSERT INTO req_ids (label)
SELECT 'r' || dept || '_' || n
FROM (VALUES ('100'), ('101'), ('102'), ('103'), ('104')) AS d(dept)
CROSS JOIN generate_series(1, 9) AS n;

-- ---------------------------------------------------------------------
-- 1) Birimler (departments) — 5 yeni birim. Mevcut id'lerle (3,4,10,11)
--    çakışmaması için 100-104 aralığı kullanılıyor.
-- ---------------------------------------------------------------------
INSERT INTO public.departments (id, name, is_active) VALUES
    (100, 'Bilgi İşlem', true),
    (101, 'İnsan Kaynakları', true),
    (102, 'Temizlik ve Peyzaj', true),
    (103, 'Ulaşım ve Trafik', true),
    (104, 'Halkla İlişkiler', true);

-- Identity sequence'i elle verilen id'lerin üzerine çekiyoruz, aksi halde
-- sonraki normal (uygulama üzerinden) birim eklemede çakışma olabilir.
SELECT setval('public.departments_id_seq', (SELECT max(id) FROM public.departments));

-- ---------------------------------------------------------------------
-- 2) Davet kodları (personnel_invites) — personel/müdür/admin kaydı için.
--    handle_new_user() bunları auth.users insert'i sırasında "kullanıldı"
--    olarak işaretleyecek.
-- ---------------------------------------------------------------------
INSERT INTO public.personnel_invites (code, department_id, role) VALUES
    ('SEEDADM100',  100, 'admin'),
    ('SEEDMUD100',  100, 'mudur'),
    ('SEEDMUD101',  101, 'mudur'),
    ('SEEDMUD102',  102, 'mudur'),
    ('SEEDMUD103',  103, 'mudur'),
    ('SEEDMUD104',  104, 'mudur'),
    ('SEEDPER100A', 100, 'personel'),
    ('SEEDPER100B', 100, 'personel'),
    ('SEEDPER101A', 101, 'personel'),
    ('SEEDPER101B', 101, 'personel'),
    ('SEEDPER102A', 102, 'personel'),
    ('SEEDPER102B', 102, 'personel'),
    ('SEEDPER103A', 103, 'personel'),
    ('SEEDPER103B', 103, 'personel'),
    ('SEEDPER104A', 104, 'personel'),
    ('SEEDPER104B', 104, 'personel');

-- ---------------------------------------------------------------------
-- 3) Kullanıcılar — auth.users + auth.identities. Her satırın
--    raw_user_meta_data'sı, Flutter'ın signUp() çağrısının gönderdiği
--    alanları birebir taklit ediyor (full_name/tc_no/phone/il/ilce/
--    invite_code) — bu sayede handle_new_user() trigger'ı public.users +
--    public.users_private satırlarını OTOMATİK ve doğru şekilde oluşturuyor.
-- ---------------------------------------------------------------------
INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    is_sso_user, is_anonymous
)
SELECT
    '00000000-0000-0000-0000-000000000000',
    s.id,
    'authenticated',
    'authenticated',
    v.email,
    crypt('Test1234!', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    v.meta,
    now(),
    now(),
    '', '', '', '',
    false, false
FROM (VALUES
    ('admin_2',   'seed.admin2@tsys.local',   jsonb_build_object('full_name','Zeynep Aydın',   'tc_no','10000000010','phone','+905000000001','il','İstanbul',  'ilce','Kadıköy',      'invite_code','SEEDADM100')),
    ('mudur_100', 'seed.mudur100@tsys.local', jsonb_build_object('full_name','Hakan Yıldız',   'tc_no','10000000011','phone','+905000000002','il','Ankara',     'ilce','Çankaya',      'invite_code','SEEDMUD100')),
    ('mudur_101', 'seed.mudur101@tsys.local', jsonb_build_object('full_name','Sevgi Arslan',   'tc_no','10000000012','phone','+905000000003','il','İzmir',      'ilce','Bornova',      'invite_code','SEEDMUD101')),
    ('mudur_102', 'seed.mudur102@tsys.local', jsonb_build_object('full_name','Osman Koç',      'tc_no','10000000013','phone','+905000000004','il','Bursa',      'ilce','Nilüfer',      'invite_code','SEEDMUD102')),
    ('mudur_103', 'seed.mudur103@tsys.local', jsonb_build_object('full_name','Nurcan Aksoy',   'tc_no','10000000014','phone','+905000000005','il','Antalya',    'ilce','Muratpaşa',    'invite_code','SEEDMUD103')),
    ('mudur_104', 'seed.mudur104@tsys.local', jsonb_build_object('full_name','Kerem Doğan',    'tc_no','10000000015','phone','+905000000006','il','Konya',      'ilce','Selçuklu',     'invite_code','SEEDMUD104')),
    ('per_100a',  'seed.per100a@tsys.local',  jsonb_build_object('full_name','Burak Şen',      'tc_no','10000000016','phone','+905000000007','il','Adana',      'ilce','Seyhan',       'invite_code','SEEDPER100A')),
    ('per_100b',  'seed.per100b@tsys.local',  jsonb_build_object('full_name','Elif Korkmaz',   'tc_no','10000000017','phone','+905000000008','il','Gaziantep',  'ilce','Şehitkamil',   'invite_code','SEEDPER100B')),
    ('per_101a',  'seed.per101a@tsys.local',  jsonb_build_object('full_name','Deniz Yavuz',    'tc_no','10000000018','phone','+905000000009','il','Kayseri',    'ilce','Melikgazi',    'invite_code','SEEDPER101A')),
    ('per_101b',  'seed.per101b@tsys.local',  jsonb_build_object('full_name','Gizem Polat',    'tc_no','10000000019','phone','+905000000010','il','Eskişehir',  'ilce','Odunpazarı',   'invite_code','SEEDPER101B')),
    ('per_102a',  'seed.per102a@tsys.local',  jsonb_build_object('full_name','Murat Aydemir',  'tc_no','10000000020','phone','+905000000011','il','Trabzon',    'ilce','Ortahisar',    'invite_code','SEEDPER102A')),
    ('per_102b',  'seed.per102b@tsys.local',  jsonb_build_object('full_name','Selin Kurt',     'tc_no','10000000021','phone','+905000000012','il','Samsun',     'ilce','İlkadım',      'invite_code','SEEDPER102B')),
    ('per_103a',  'seed.per103a@tsys.local',  jsonb_build_object('full_name','Emre Bulut',     'tc_no','10000000022','phone','+905000000013','il','Mersin',     'ilce','Yenişehir',    'invite_code','SEEDPER103A')),
    ('per_103b',  'seed.per103b@tsys.local',  jsonb_build_object('full_name','Aslı Güneş',     'tc_no','10000000023','phone','+905000000014','il','Denizli',    'ilce','Pamukkale',    'invite_code','SEEDPER103B')),
    ('per_104a',  'seed.per104a@tsys.local',  jsonb_build_object('full_name','Tolga Er',       'tc_no','10000000024','phone','+905000000015','il','Kocaeli',    'ilce','İzmit',        'invite_code','SEEDPER104A')),
    ('per_104b',  'seed.per104b@tsys.local',  jsonb_build_object('full_name','Merve Aktaş',    'tc_no','10000000025','phone','+905000000016','il','Sakarya',    'ilce','Adapazarı',    'invite_code','SEEDPER104B')),
    ('vat_1',     'seed.vat1@tsys.local',     jsonb_build_object('full_name','Ali Vural',      'tc_no','10000000026','phone','+905000000017','il','Manisa',     'ilce','Şehzadeler')),
    ('vat_2',     'seed.vat2@tsys.local',     jsonb_build_object('full_name','Fatma Öz',       'tc_no','10000000027','phone','+905000000018','il','Balıkesir',  'ilce','Altıeylül')),
    ('vat_3',     'seed.vat3@tsys.local',     jsonb_build_object('full_name','Cemal Bora',     'tc_no','10000000028','phone','+905000000019','il','Aydın',      'ilce','Efeler')),
    ('vat_4',     'seed.vat4@tsys.local',     jsonb_build_object('full_name','Hülya Uçar',     'tc_no','10000000029','phone','+905000000020','il','Muğla',      'ilce','Menteşe'))
) AS v(label, email, meta)
JOIN seed_ids s ON s.label = v.label;

-- auth.identities — GoTrue'nun email/password sağlayıcısı için beklediği
-- eşlik eden kimlik kaydı (gerçek signUp()'ın oluşturduğu satırla aynı desen).
INSERT INTO auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
SELECT
    gen_random_uuid(),
    s.id::text,
    s.id,
    v.meta || jsonb_build_object('sub', s.id::text, 'email', v.email, 'email_verified', false, 'phone_verified', false),
    'email',
    now(), now(), now()
FROM (VALUES
    ('admin_2',   'seed.admin2@tsys.local',   jsonb_build_object('full_name','Zeynep Aydın',   'tc_no','10000000010','phone','+905000000001','il','İstanbul',  'ilce','Kadıköy',      'invite_code','SEEDADM100')),
    ('mudur_100', 'seed.mudur100@tsys.local', jsonb_build_object('full_name','Hakan Yıldız',   'tc_no','10000000011','phone','+905000000002','il','Ankara',     'ilce','Çankaya',      'invite_code','SEEDMUD100')),
    ('mudur_101', 'seed.mudur101@tsys.local', jsonb_build_object('full_name','Sevgi Arslan',   'tc_no','10000000012','phone','+905000000003','il','İzmir',      'ilce','Bornova',      'invite_code','SEEDMUD101')),
    ('mudur_102', 'seed.mudur102@tsys.local', jsonb_build_object('full_name','Osman Koç',      'tc_no','10000000013','phone','+905000000004','il','Bursa',      'ilce','Nilüfer',      'invite_code','SEEDMUD102')),
    ('mudur_103', 'seed.mudur103@tsys.local', jsonb_build_object('full_name','Nurcan Aksoy',   'tc_no','10000000014','phone','+905000000005','il','Antalya',    'ilce','Muratpaşa',    'invite_code','SEEDMUD103')),
    ('mudur_104', 'seed.mudur104@tsys.local', jsonb_build_object('full_name','Kerem Doğan',    'tc_no','10000000015','phone','+905000000006','il','Konya',      'ilce','Selçuklu',     'invite_code','SEEDMUD104')),
    ('per_100a',  'seed.per100a@tsys.local',  jsonb_build_object('full_name','Burak Şen',      'tc_no','10000000016','phone','+905000000007','il','Adana',      'ilce','Seyhan',       'invite_code','SEEDPER100A')),
    ('per_100b',  'seed.per100b@tsys.local',  jsonb_build_object('full_name','Elif Korkmaz',   'tc_no','10000000017','phone','+905000000008','il','Gaziantep',  'ilce','Şehitkamil',   'invite_code','SEEDPER100B')),
    ('per_101a',  'seed.per101a@tsys.local',  jsonb_build_object('full_name','Deniz Yavuz',    'tc_no','10000000018','phone','+905000000009','il','Kayseri',    'ilce','Melikgazi',    'invite_code','SEEDPER101A')),
    ('per_101b',  'seed.per101b@tsys.local',  jsonb_build_object('full_name','Gizem Polat',    'tc_no','10000000019','phone','+905000000010','il','Eskişehir',  'ilce','Odunpazarı',   'invite_code','SEEDPER101B')),
    ('per_102a',  'seed.per102a@tsys.local',  jsonb_build_object('full_name','Murat Aydemir',  'tc_no','10000000020','phone','+905000000011','il','Trabzon',    'ilce','Ortahisar',    'invite_code','SEEDPER102A')),
    ('per_102b',  'seed.per102b@tsys.local',  jsonb_build_object('full_name','Selin Kurt',     'tc_no','10000000021','phone','+905000000012','il','Samsun',     'ilce','İlkadım',      'invite_code','SEEDPER102B')),
    ('per_103a',  'seed.per103a@tsys.local',  jsonb_build_object('full_name','Emre Bulut',     'tc_no','10000000022','phone','+905000000013','il','Mersin',     'ilce','Yenişehir',    'invite_code','SEEDPER103A')),
    ('per_103b',  'seed.per103b@tsys.local',  jsonb_build_object('full_name','Aslı Güneş',     'tc_no','10000000023','phone','+905000000014','il','Denizli',    'ilce','Pamukkale',    'invite_code','SEEDPER103B')),
    ('per_104a',  'seed.per104a@tsys.local',  jsonb_build_object('full_name','Tolga Er',       'tc_no','10000000024','phone','+905000000015','il','Kocaeli',    'ilce','İzmit',        'invite_code','SEEDPER104A')),
    ('per_104b',  'seed.per104b@tsys.local',  jsonb_build_object('full_name','Merve Aktaş',    'tc_no','10000000025','phone','+905000000016','il','Sakarya',    'ilce','Adapazarı',    'invite_code','SEEDPER104B')),
    ('vat_1',     'seed.vat1@tsys.local',     jsonb_build_object('full_name','Ali Vural',      'tc_no','10000000026','phone','+905000000017','il','Manisa',     'ilce','Şehzadeler')),
    ('vat_2',     'seed.vat2@tsys.local',     jsonb_build_object('full_name','Fatma Öz',       'tc_no','10000000027','phone','+905000000018','il','Balıkesir',  'ilce','Altıeylül')),
    ('vat_3',     'seed.vat3@tsys.local',     jsonb_build_object('full_name','Cemal Bora',     'tc_no','10000000028','phone','+905000000019','il','Aydın',      'ilce','Efeler')),
    ('vat_4',     'seed.vat4@tsys.local',     jsonb_build_object('full_name','Hülya Uçar',     'tc_no','10000000029','phone','+905000000020','il','Muğla',      'ilce','Menteşe'))
) AS v(label, email, meta)
JOIN seed_ids s ON s.label = v.label;

-- ---------------------------------------------------------------------
-- 4) Talepler (requests) — 5 birim × 9 talep = 45 talep. Her birimde
--    durum çeşitliliği: 2 yeni (acik/atanmamış), 2 işlemde (acik/atanmış),
--    2 çözüldü (onay bekliyor), 2 onaylandı, 1 reddedildi.
--    Hepsi başlangıçta status='acik' ile giriliyor; 'cozuldu'/'onaylandi'/
--    'reddedildi' durumları adım 5'teki results akışıyla DOĞAL olarak
--    (trigger zinciriyle) oluşacak.
-- ---------------------------------------------------------------------
INSERT INTO public.requests (id, title, description, category, status, requester_type, department_id, created_by, assigned_to)
SELECT
    r.id,
    v.title,
    v.description,
    v.category,
    'acik',
    v.requester_type,
    v.department_id,
    (SELECT id FROM seed_ids WHERE label = v.created_by_label),
    CASE WHEN v.assigned_label IS NULL THEN NULL ELSE (SELECT id FROM seed_ids WHERE label = v.assigned_label) END
FROM (VALUES
    -- Bilgi İşlem (100)
    ('r100_1', 'Bilgisayar Arızası',        'Ofisimdeki masaüstü bilgisayar açılmıyor, güç düğmesine basınca tepki vermiyor.',           'Bilgisayar Arızası',        'vatandas', 100, 'vat_1',    NULL),
    ('r100_2', 'İnternet Bağlantı Sorunu',  'Kat genelinde internet bağlantısı çok yavaş, dosya paylaşımı yapılamıyor.',                 'İnternet Bağlantı Sorunu',  'personel', 100, 'per_101a', NULL),
    ('r100_3', 'Yazıcı Arızası',            '3. kattaki ağ yazıcısı kağıt sıkıştırıyor, sürekli hata veriyor.',                          'Yazıcı Arızası',            'vatandas', 100, 'vat_2',    'per_100a'),
    ('r100_4', 'Şifre Sıfırlama Talebi',    'Kurumsal e-posta hesabıma giriş yapamıyorum, şifremi unuttum.',                             'Şifre Sıfırlama Talebi',    'personel', 100, 'per_101a', 'per_100b'),
    ('r100_5', 'Yazılım Kurulum Talebi',    'Muhasebe programının güncel sürümü bilgisayarıma kurulmadı.',                               'Yazılım Kurulum Talebi',    'vatandas', 100, 'vat_3',    'per_100a'),
    ('r100_6', 'VPN Bağlantı Sorunu',       'Uzaktan çalışırken VPN bağlantısı sürekli düşüyor.',                                        'VPN Bağlantı Sorunu',       'personel', 100, 'per_101a', 'per_100b'),
    ('r100_7', 'Telefon Santral Arızası',   'Dahili telefon hattım çalışmıyor, dışarıdan aranamıyorum.',                                  'Telefon Santral Arızası',   'vatandas', 100, 'vat_4',    'per_100a'),
    ('r100_8', 'Ekran Kartı Arızası',       'Bilgisayarımın ekranı titriyor ve renk bozulmaları var.',                                    'Ekran Kartı Arızası',       'personel', 100, 'per_101a', 'per_100b'),
    ('r100_9', 'Klavye/Mouse Arızası',      'Kablosuz klavyem rastgele karakterler yazıyor.',                                             'Klavye/Mouse Arızası',      'vatandas', 100, 'vat_1',    'per_100a'),

    -- İnsan Kaynakları (101)
    ('r101_1', 'İzin Talebi Onayı',         'Yıllık izin talebimin sistemde hala işlenmediğini fark ettim.',                              'İzin Talebi Onayı',         'vatandas', 101, 'vat_2',    NULL),
    ('r101_2', 'Bordro Hatası',             'Bu ayki bordromda mesai ücretleri hatalı hesaplanmış.',                                      'Bordro Hatası',             'personel', 101, 'per_102a', NULL),
    ('r101_3', 'Özlük Bilgisi Güncelleme',  'Adres bilgilerim değişti, güncellenmesini istiyorum.',                                       'Özlük Bilgisi Güncelleme',  'vatandas', 101, 'vat_3',    'per_101a'),
    ('r101_4', 'Yeni Personel Oryantasyonu','Yeni başlayan personel için oryantasyon programı talep ediyorum.',                           'Yeni Personel Oryantasyonu','personel', 101, 'per_102a', 'per_101b'),
    ('r101_5', 'İşe Giriş Belgesi Talebi',  'SGK işe giriş bildirgemin bir örneğine ihtiyacım var.',                                       'İşe Giriş Belgesi Talebi',  'vatandas', 101, 'vat_4',    'per_101a'),
    ('r101_6', 'Kıdem Tazminatı Sorgusu',   'Kıdem tazminatı hesaplamamla ilgili bilgi almak istiyorum.',                                  'Kıdem Tazminatı Sorgusu',   'personel', 101, 'per_102a', 'per_101b'),
    ('r101_7', 'Sağlık Sigortası Kaydı',    'Özel sağlık sigortası kaydımın yapılmadığını fark ettim.',                                    'Sağlık Sigortası Kaydı',    'vatandas', 101, 'vat_1',    'per_101a'),
    ('r101_8', 'Performans Değ. İtirazı',   'Son performans değerlendirme puanıma itiraz etmek istiyorum.',                                'Performans Değ. İtirazı',   'personel', 101, 'per_102a', 'per_101b'),
    ('r101_9', 'Mesai Ücreti Hesaplama',    'Geçen ayki fazla mesai saatlerim bordroya yansımamış.',                                        'Mesai Ücreti Hesaplama',    'vatandas', 101, 'vat_2',    'per_101a'),

    -- Temizlik ve Peyzaj (102)
    ('r102_1', 'Ofis Temizlik Talebi',      '2. kat tuvaletleri iki gündür temizlenmedi.',                                                 'Ofis Temizlik Talebi',      'vatandas', 102, 'vat_3',    NULL),
    ('r102_2', 'Bahçe Bakım Talebi',        'Bina önündeki çim alan uzun süredir biçilmedi.',                                              'Bahçe Bakım Talebi',        'personel', 102, 'per_103a', NULL),
    ('r102_3', 'Çöp Toplama Sorunu',        'Arka bahçedeki çöp konteynerleri taşıyor, toplanması gerekiyor.',                             'Çöp Toplama Sorunu',        'vatandas', 102, 'vat_4',    'per_102a'),
    ('r102_4', 'Halı Yıkama Talebi',        'Toplantı salonundaki halıda leke var, yıkanmasını istiyorum.',                                'Halı Yıkama Talebi',        'personel', 102, 'per_103a', 'per_102b'),
    ('r102_5', 'Cam Temizliği Talebi',      'Bina dış cephesindeki camlar kirlendi, temizlenmesi gerekiyor.',                              'Cam Temizliği Talebi',      'vatandas', 102, 'vat_1',    'per_102a'),
    ('r102_6', 'Ağaç Budama Talebi',        'Otopark girişindeki ağaç dalları görüşü engelliyor.',                                         'Ağaç Budama Talebi',        'personel', 102, 'per_103a', 'per_102b'),
    ('r102_7', 'Zararlı Böcek İlaçlama',    'Depo bölümünde böcek istilası var, ilaçlama gerekiyor.',                                       'Zararlı Böcek İlaçlama',    'vatandas', 102, 'vat_2',    'per_102a'),
    ('r102_8', 'Klima Filtre Temizliği',    'Ofis klimalarından kötü koku geliyor, filtre temizliği gerekiyor.',                            'Klima Filtre Temizliği',    'personel', 102, 'per_103a', 'per_102b'),
    ('r102_9', 'Sulama Sistemi Arızası',    'Bahçedeki otomatik sulama sistemi çalışmıyor.',                                                'Sulama Sistemi Arızası',    'vatandas', 102, 'vat_3',    'per_102a'),

    -- Ulaşım ve Trafik (103)
    ('r103_1', 'Servis Aracı Arızası',      'Personel servis aracının klimaları çalışmıyor.',                                              'Servis Aracı Arızası',      'vatandas', 103, 'vat_4',    NULL),
    ('r103_2', 'Otopark Sorunu',            'Ziyaretçi otoparkında aydınlatma yetersiz.',                                                  'Otopark Sorunu',            'personel', 103, 'per_104a', NULL),
    ('r103_3', 'Trafik İşareti Talebi',     'Bina girişine yaya geçidi levhası konulmasını istiyorum.',                                    'Trafik İşareti Talebi',     'vatandas', 103, 'vat_1',    'per_103a'),
    ('r103_4', 'Yol Bakım Talebi',          'Otopark girişindeki asfaltta büyük bir çukur var.',                                           'Yol Bakım Talebi',          'personel', 103, 'per_104a', 'per_103b'),
    ('r103_5', 'Servis Güzergahı Değişikliği','Servis aracının güzergahı benim durağıma uğramıyor.',                                       'Servis Güzergahı Değişikliği','vatandas', 103, 'vat_2',  'per_103a'),
    ('r103_6', 'Araç Yakıt Kartı Sorunu',   'Kurumsal yakıt kartım pompalarda çalışmıyor.',                                                'Araç Yakıt Kartı Sorunu',   'personel', 103, 'per_104a', 'per_103b'),
    ('r103_7', 'Bisiklet Park Alanı Talebi','Bina önünde bisiklet park alanı oluşturulmasını istiyorum.',                                   'Bisiklet Park Alanı Talebi','vatandas', 103, 'vat_3',    'per_103a'),
    ('r103_8', 'Engelli Rampası Talebi',    'Ana giriş kapısında tekerlekli sandalye rampası eksik.',                                       'Engelli Rampası Talebi',    'personel', 103, 'per_104a', 'per_103b'),
    ('r103_9', 'Araç Bakım Gecikmesi',      'Filodaki aracın periyodik bakımı geciktirildi.',                                               'Araç Bakım Gecikmesi',      'vatandas', 103, 'vat_4',    'per_103a'),

    -- Halkla İlişkiler (104)
    ('r104_1', 'Vatandaş Şikayeti Yönlendirme','Sosyal medyada kuruma yönelik bir şikayet aldım, yönlendirme istiyorum.',                  'Vatandaş Şikayeti Yönlendirme','vatandas', 104, 'vat_1', NULL),
    ('r104_2', 'Basın Açıklaması Talebi',   'Geçen haftaki etkinlikle ilgili basın açıklaması hazırlanmasını istiyorum.',                  'Basın Açıklaması Talebi',   'personel', 104, 'per_100a', NULL),
    ('r104_3', 'Etkinlik Organizasyon Talebi','Kurum tanıtım günü için organizasyon desteği talep ediyorum.',                              'Etkinlik Organizasyon Talebi','vatandas', 104, 'vat_2',  'per_104a'),
    ('r104_4', 'Web Sitesi İçerik Güncelleme','Kurumsal web sitesindeki iletişim bilgileri güncel değil.',                                 'Web Sitesi İçerik Güncelleme','personel', 104, 'per_100a','per_104b'),
    ('r104_5', 'Kurumsal Kimlik Talebi',    'Yeni broşür tasarımı için kurumsal kimlik dosyalarına ihtiyacım var.',                        'Kurumsal Kimlik Talebi',    'vatandas', 104, 'vat_3',    'per_104a'),
    ('r104_6', 'Basın Bülteni Hazırlama',   'Yeni proje için basın bülteni hazırlanmasını istiyorum.',                                     'Basın Bülteni Hazırlama',   'personel', 104, 'per_100a', 'per_104b'),
    ('r104_7', 'Sosyal Medya Şikayeti',     'Kurumun Instagram hesabına gelen olumsuz yorumlar yanıtlanmıyor.',                            'Sosyal Medya Şikayeti',     'vatandas', 104, 'vat_4',    'per_104a'),
    ('r104_8', 'Anket Sonuçları Talebi',    'Vatandaş memnuniyet anketinin sonuçlarına ihtiyacım var.',                                    'Anket Sonuçları Talebi',    'personel', 104, 'per_100a', 'per_104b'),
    ('r104_9', 'Fotoğraf Çekim Talebi',     'Yeni personel tanıtım fotoğraflarının çekilmesini istiyorum.',                                'Fotoğraf Çekim Talebi',     'vatandas', 104, 'vat_1',    'per_104a')
) AS v(label, title, description, category, requester_type, department_id, created_by_label, assigned_label)
JOIN req_ids r ON r.label = v.label;

-- ---------------------------------------------------------------------
-- 5) Sonuçlar (results) — sadece 5/6/7/8/9 numaralı satırlar için.
--    Önce hepsi 'beklemede' olarak giriliyor (sync trigger'ı status'u
--    otomatik 'cozuldu' yapar); ardından hedefi 'onaylandi'/'reddedildi'
--    olanlar için ikinci bir UPDATE ile onay/red işleniyor — bu, gerçek
--    personel/müdür akışının doğal iki adımını taklit ediyor ve
--    log_result_resolved/log_result_updated/sync_request_status_from_result
--    trigger'larının hepsini doğru sırayla tetikliyor.
-- ---------------------------------------------------------------------
INSERT INTO public.results (request_id, report_text, resolved_by, approval_status)
SELECT
    (SELECT id FROM req_ids WHERE label = v.label),
    v.report_text,
    (SELECT id FROM seed_ids WHERE label = v.resolved_by_label),
    'beklemede'
FROM (VALUES
    ('r100_5', 'Muhasebe programının güncel sürümü uzaktan kurulum aracıyla bilgisayara yüklendi.', 'per_100a'),
    ('r100_6', 'VPN istemcisi güncellendi ve bağlantı kararlılığı test edildi, sorun giderildi.',    'per_100b'),
    ('r100_7', 'Dahili hat üzerindeki arızalı port değiştirildi, telefon test edildi.',               'per_100a'),
    ('r100_8', 'Ekran kartı sürücüleri güncellendi, görüntü bozulmaları giderildi.',                  'per_100b'),
    ('r100_9', 'Klavye pil değişikliği ve alıcı sıfırlaması yapıldı, sorun giderildi.',               'per_100a'),

    ('r101_5', 'SGK işe giriş bildirgesinin bir örneği personele e-posta ile iletildi.',              'per_101a'),
    ('r101_6', 'Kıdem tazminatı hesaplaması yapılıp personele yazılı olarak bildirildi.',             'per_101b'),
    ('r101_7', 'Özel sağlık sigortası kaydı sisteme işlendi ve poliçe personele iletildi.',            'per_101a'),
    ('r101_8', 'Performans değerlendirme itirazı incelendi, yeni puan komisyona sunuldu.',            'per_101b'),
    ('r101_9', 'Fazla mesai saatleri yeniden hesaplanıp bordroya yansıtıldı.',                        'per_101a'),

    ('r102_5', 'Bina dış cephesindeki camlar profesyonel ekip tarafından temizlendi.',                'per_102a'),
    ('r102_6', 'Görüşü engelleyen ağaç dalları budandı.',                                             'per_102b'),
    ('r102_7', 'Depo bölümü ilaçlandı, böcek istilası giderildi.',                                    'per_102a'),
    ('r102_8', 'Klima filtreleri temizlendi ve değiştirildi, koku giderildi.',                        'per_102b'),
    ('r102_9', 'Sulama sistemindeki arızalı vana değiştirildi, sistem test edildi.',                  'per_102a'),

    ('r103_5', 'Servis güzergahı gözden geçirilip ilgili durak eklendi.',                             'per_103a'),
    ('r103_6', 'Yakıt kartı sağlayıcıyla iletişime geçilip kart yeniden aktifleştirildi.',            'per_103b'),
    ('r103_7', 'Bina önüne bisiklet park alanı için stant yerleştirildi.',                            'per_103a'),
    ('r103_8', 'Ana giriş kapısına tekerlekli sandalye rampası monte edildi.',                        'per_103b'),
    ('r103_9', 'Araç periyodik bakıma alındı ve teslim edildi.',                                      'per_103a'),

    ('r104_5', 'Kurumsal kimlik dosyaları hazırlanıp ilgili birime iletildi.',                        'per_104a'),
    ('r104_6', 'Basın bülteni hazırlanıp onaya sunuldu.',                                             'per_104b'),
    ('r104_7', 'Sosyal medya yorumlarına yanıt verildi, moderasyon süreci başlatıldı.',               'per_104a'),
    ('r104_8', 'Vatandaş memnuniyet anketi sonuçları raporlanıp iletildi.',                           'per_104b'),
    ('r104_9', 'Personel tanıtım fotoğraf çekimi planlandı ve gerçekleştirildi.',                     'per_104a')
) AS v(label, report_text, resolved_by_label);

-- Onaylanan talepler (7 ve 8 numaralı satırlar) — ikinci adım: müdür onayı.
UPDATE public.results
SET approval_status = 'onaylandi',
    approved_by = (SELECT id FROM seed_ids WHERE label = m.mudur_label)
FROM (VALUES
    ('r100_7', 'mudur_100'), ('r100_8', 'mudur_100'),
    ('r101_7', 'mudur_101'), ('r101_8', 'mudur_101'),
    ('r102_7', 'mudur_102'), ('r102_8', 'mudur_102'),
    ('r103_7', 'mudur_103'), ('r103_8', 'mudur_103'),
    ('r104_7', 'mudur_104'), ('r104_8', 'mudur_104')
) AS m(label, mudur_label)
WHERE results.request_id = (SELECT id FROM req_ids WHERE label = m.label);

-- Reddedilen talepler (9 numaralı satır) — ikinci adım: müdür reddi.
UPDATE public.results
SET approval_status = 'reddedildi',
    approved_by = (SELECT id FROM seed_ids WHERE label = m.mudur_label)
FROM (VALUES
    ('r100_9', 'mudur_100'),
    ('r101_9', 'mudur_101'),
    ('r102_9', 'mudur_102'),
    ('r103_9', 'mudur_103'),
    ('r104_9', 'mudur_104')
) AS m(label, mudur_label)
WHERE results.request_id = (SELECT id FROM req_ids WHERE label = m.label);

-- ---------------------------------------------------------------------
-- 6) Değerlendirmeler (request_ratings) — sadece onaylanmış (7 ve 8
--    numaralı) taleplerde. rate_request() RPC'sinin yaptığı iki adımı
--    (rating insert + 'rated' geçmiş kaydı) elle taklit ediyoruz çünkü
--    RPC auth.uid() gerektiriyor ve burada bir oturum yok.
-- ---------------------------------------------------------------------
INSERT INTO public.request_ratings (request_id, personnel_id, rated_by, rating, comment)
SELECT
    (SELECT id FROM req_ids WHERE label = v.label),
    (SELECT resolved_by FROM public.results WHERE request_id = (SELECT id FROM req_ids WHERE label = v.label)),
    (SELECT created_by FROM public.requests WHERE id = (SELECT id FROM req_ids WHERE label = v.label)),
    v.rating,
    v.comment
FROM (VALUES
    ('r100_7', 5, 'Çok hızlı ve nazik bir şekilde çözüldü, teşekkürler.'),
    ('r100_8', 4, 'Sorun giderildi ama biraz zaman aldı.'),
    ('r101_7', 5, 'İlgi ve çözüm için teşekkür ederim.'),
    ('r101_8', 3, 'Sonuç tatmin edici ama süreç yavaş işledi.'),
    ('r102_7', 4, 'Sorun kısa sürede giderildi.'),
    ('r102_8', 5, 'Çok teşekkürler, harika bir hizmet aldım.'),
    ('r103_7', 4, 'Talep edilen düzenleme yapıldı.'),
    ('r103_8', 5, 'Beklentimin üzerinde bir hizmet, çok memnun kaldım.'),
    ('r104_7', 3, 'Cevap biraz gecikmeli oldu ama sonuçtan memnunum.'),
    ('r104_8', 4, 'Talebim düzgün şekilde sonuçlandırıldı.')
) AS v(label, rating, comment);

INSERT INTO public.request_history (request_id, event_type, actor_id, actor_label, detail)
SELECT
    (SELECT id FROM req_ids WHERE label = v.label),
    'rated',
    (SELECT created_by FROM public.requests WHERE id = (SELECT id FROM req_ids WHERE label = v.label)),
    'Talebi açan kişi',
    jsonb_build_object('rating', v.rating, 'comment', v.comment)
FROM (VALUES
    ('r100_7', 5, 'Çok hızlı ve nazik bir şekilde çözüldü, teşekkürler.'),
    ('r100_8', 4, 'Sorun giderildi ama biraz zaman aldı.'),
    ('r101_7', 5, 'İlgi ve çözüm için teşekkür ederim.'),
    ('r101_8', 3, 'Sonuç tatmin edici ama süreç yavaş işledi.'),
    ('r102_7', 4, 'Sorun kısa sürede giderildi.'),
    ('r102_8', 5, 'Çok teşekkürler, harika bir hizmet aldım.'),
    ('r103_7', 4, 'Talep edilen düzenleme yapıldı.'),
    ('r103_8', 5, 'Beklentimin üzerinde bir hizmet, çok memnun kaldım.'),
    ('r104_7', 3, 'Cevap biraz gecikmeli oldu ama sonuçtan memnunum.'),
    ('r104_8', 4, 'Talebim düzgün şekilde sonuçlandırıldı.')
) AS v(label, rating, comment);

COMMIT;
