import 'package:flutter/material.dart';

import 'query_result_screen.dart';
import 'request_create_screen.dart';

/// Giriş yapmadan devam eden vatandaşa gösterilen menü (bkz. CLAUDE.md —
/// hibrit vatandaş erişimi modeli).
class CitizenGuestMenuScreen extends StatelessWidget {
  const CitizenGuestMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Giriş Yapmadan Devam Et')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RequestCreateScreen()),
                  ),
                  child: const Text('Talep Oluştur'),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const QueryResultScreen()),
                  ),
                  child: const Text('Sonucu Sorgula'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
