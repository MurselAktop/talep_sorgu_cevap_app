import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase bağlantısını başlatır ve istemciye erişim sağlar.
class SupabaseService {
  static Future<void> initialize() async {
    var url = dotenv.env['SUPABASE_URL']!;
    // Android'de host makineye ulaşım, emülatör mü gerçek cihaz mı olduğuna
    // göre farklıdır:
    // - Emülatör: "localhost" emülatörün kendisini işaret eder; host'a
    //   ulaşmak için sabit 10.0.2.2 adresi kullanılmalı.
    // - Gerçek cihaz (USB): "localhost" burada da cihazın kendisini işaret
    //   eder, ama 10.0.2.2 gerçek cihazda tanımsız/geçersizdir. Bunun yerine
    //   geliştiricinin `adb reverse tcp:8000 tcp:8000` çalıştırmış olduğu
    //   varsayılır — bu, cihazın "localhost:8000"ini host makinenin
    //   "localhost:8000"ine yönlendirir, dolayısıyla URL değiştirilmeden
    //   (localhost olarak) bırakılmalı. Bkz. CLAUDE.md "Bilinen Ortam
    //   Notları".
    if (!kIsWeb && Platform.isAndroid) {
      final isPhysicalDevice = (await DeviceInfoPlugin().androidInfo).isPhysicalDevice;
      if (!isPhysicalDevice) {
        url = url.replaceFirst('localhost', '10.0.2.2');
      }
    }
    await Supabase.initialize(
      url: url,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
