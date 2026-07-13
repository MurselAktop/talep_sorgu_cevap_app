import 'package:flutter/material.dart';

/// Geçici ana ekran (placeholder). Talep listeleme ekranı yazılınca bunun
/// yerini alacak. Şimdilik role göre farklı yönlendirme yapılmıyor; herkes
/// giriş yaptıktan sonra buraya düşüyor (bkz. CLAUDE.md yol haritası, madde 5).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TŞYS — Talep ve Şikâyet Yönetim Sistemi')),
      body: const Center(
        child: Text('Talep ve Şikâyet Yönetim Sistemi'),
      ),
    );
  }
}
