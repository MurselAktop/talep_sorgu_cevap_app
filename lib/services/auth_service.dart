import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Kimlik doğrulama (kayıt/giriş) işlemlerini yönetir.
class AuthService {
  static SupabaseClient get _client => SupabaseService.client;

  /// Vatandaş kaydı oluşturur. `fullName`, Supabase Auth'un kullanıcı
  /// metadata'sına (`raw_user_meta_data`) yazılır; veritabanındaki
  /// `handle_new_user` trigger'ı bunu okuyup `public.users` tablosuna
  /// `role = 'vatandas'`, `department_id = null` ile otomatik ekler.
  /// Bu yüzden burada ayrıca `public.users`'a manuel INSERT yapılmaz.
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
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
