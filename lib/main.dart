import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await SupabaseService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TŞYS',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const AuthGate(),
    );
  }
}

/// Uygulama açılışında mevcut bir Supabase oturumu olup olmadığına bakar:
/// varsa doğrudan ana ekrana (HomePage), yoksa giriş ekranına yönlendirir.
/// Role göre farklı yönlendirme (vatandaş/personel/müdür/admin) talep
/// listeleme ekranı yazılınca eklenecek — bkz. CLAUDE.md yol haritası.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final hasSession = SupabaseService.client.auth.currentSession != null;
    return hasSession ? const HomePage() : const LoginScreen();
  }
}
