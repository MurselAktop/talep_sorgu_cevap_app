import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Kimlik doğrulama (kayıt/giriş) işlemlerini yönetir.
class AuthService {
  static SupabaseClient get _client => SupabaseService.client;

  /// Vatandaş ya da personel/müdür/admin kaydı oluşturur. `fullName`,
  /// Supabase Auth'un kullanıcı metadata'sına (`raw_user_meta_data`) yazılır;
  /// veritabanındaki `handle_new_user` trigger'ı bunu okuyup `public.users`
  /// tablosuna otomatik profil ekler. Bu yüzden burada ayrıca
  /// `public.users`'a manuel INSERT yapılmaz.
  ///
  /// `inviteCode` verilirse, trigger bunu `personnel_invites` tablosunda
  /// doğrulayıp kullanıcıyı kodun tanımladığı rol/birimle oluşturur (kod
  /// geçersiz/kullanılmışsa kayıt reddedilir). Verilmezse eski davranış
  /// (vatandaş kaydı) aynen çalışır.
  ///
  /// Faz 1 (2026-07-20): `tcNo`, `phone`, `il`, `ilce` tüm kayıtlar için
  /// zorunlu. Trigger, phone/il/ilce'yi `public.users`'a, tcNo'yu ise
  /// kısıtlı erişimli `public.users_private` tablosuna yazar (tc_no'yu
  /// sadece kullanıcının kendisi + admin okuyabilir).
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String tcNo,
    required String phone,
    required String il,
    required String ilce,
    String? inviteCode,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'tc_no': tcNo,
        'phone': phone,
        'il': il,
        'ilce': ilce,
        'invite_code': ?inviteCode,
      },
    );
  }

  /// Kayıt öncesi tc_no (ve verilirse davet kodu) geçerliliğini kontrol eder.
  ///
  /// ÖNEMLİ (2026-07-20 kök neden analizi): Bu kontrol BİLİNÇLİ olarak
  /// signUp()'tan AYRI bir RPC olarak yapılıyor, handle_new_user()
  /// trigger'ının kendi kontrollerine güvenilmiyor — çünkü gotrue paketi her
  /// /signup isteğine otomatik "X-Supabase-Api-Version" header'ı ekliyor ve
  /// bu, sunucudaki GoTrue'yu trigger'dan gelen HER özel Postgres hatasını
  /// generic "Database error saving new user" mesajına sarmalamaya zorluyor
  /// (paket seviyesinde sabit davranış, bizim tarafımızdan kapatılamaz).
  /// RPC çağrıları GoTrue'nun /signup sanitizasyonuna hiç girmediğinden,
  /// buradan dönen PostgrestException.message güvenilir şekilde gerçek
  /// Türkçe hata metnini taşır. Bkz. CLAUDE.md — Bilinen Ortam Notları.
  ///
  /// Trigger'daki kontroller nihai güvenlik ağı olarak AYNEN kalıyor; bu RPC
  /// sadece kullanıcıya anlamlı bir hata gösterebilmek için var.
  static Future<void> checkRegistrationAvailability({
    required String tcNo,
    String? inviteCode,
  }) {
    return _client.rpc(
      'check_registration_availability',
      params: {'p_tc_no': tcNo, 'p_invite_code': inviteCode},
    );
  }

  /// E-posta + şifre ile giriş yapar. Hatalı kimlik bilgisi veya
  /// onaylanmamış hesap gibi durumlarda Supabase bir `AuthException` fırlatır;
  /// bu fonksiyon onu doğrudan yutmaz, çağıran taraf (ekran) yakalayıp
  /// kullanıcıya Türkçe bir mesaj gösterir.
  static Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }
}
