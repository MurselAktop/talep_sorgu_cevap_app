import 'package:flutter/material.dart';

import '../services/local_prefs_service.dart';

/// Uygulama genelinde aktif temayı (açık/koyu) tutan tek kaynak.
///
/// `main.dart`'taki `MyApp`, bunu dinleyip `MaterialApp.themeMode`'u
/// güncelliyor; `settings_screen.dart`'taki anahtar (switch) bu controller'a
/// yazıyor. Basit bir singleton `ValueNotifier` — bu küçük, uygulama
/// genelinde tek bir boolean/enum durumu için ayrı bir state management
/// paketi (Provider/Riverpod vb.) eklemek gereksiz bir bağımlılık olurdu.
class ThemeController {
  ThemeController._();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);

  static Future<void> load() async {
    mode.value = await LocalPrefsService.getThemeMode();
  }

  static Future<void> setMode(ThemeMode newMode) async {
    mode.value = newMode;
    await LocalPrefsService.setThemeMode(newMode);
  }
}
