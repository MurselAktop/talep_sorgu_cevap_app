import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';

/// Ana sayfanın AppBar'ında (bildirim zilinin solunda) gösterilen açık/koyu
/// tema anahtarı. `settings_screen.dart`'taki `_ThemeModeTile` ile AYNI
/// merkezi `ThemeController`'ı kullanıyor — tema kararı hâlâ tek bir
/// kaynaktan geliyor, burası sadece hızlı erişim için ek bir giriş noktası.
///
/// 2026-07-26 güncellemesi: tek bir tıklanabilir ikon butonu YERİNE, gerçek
/// bir kayan (`Switch`) anahtar kullanılıyor — güneş/ay ikonları anahtarın
/// içindeki hareketli topuzda (`thumbIcon`) gösteriliyor, böylece hem "kayan
/// bir switch" hissi veriyor hem de hangi temanın aktif olduğu tek bakışta
/// anlaşılıyor.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Switch(
            value: isDark,
            onChanged: (value) => ThemeController.setMode(value ? ThemeMode.dark : ThemeMode.light),
            thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
              return Icon(isDark ? Icons.dark_mode : Icons.light_mode, size: 16);
            }),
          ),
        );
      },
    );
  }
}
