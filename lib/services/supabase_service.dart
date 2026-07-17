import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase bağlantısını başlatır ve istemciye erişim sağlar.
class SupabaseService {
  static Future<void> initialize() async {
    var url = dotenv.env['SUPABASE_URL']!;
    // Android emülatöründe "localhost" host makinesini değil emülatörün
    // kendisini işaret eder; host'a ulaşmak için 10.0.2.2 kullanılmalı.
    if (!kIsWeb && Platform.isAndroid) {
      url = url.replaceFirst('localhost', '10.0.2.2');
    }
    await Supabase.initialize(
      url: url,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
