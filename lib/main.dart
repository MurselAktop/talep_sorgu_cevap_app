import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/login_screen.dart';
import 'screens/welcome_back_screen.dart';
import 'services/local_prefs_service.dart';
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

/// Uygulama açılışında, giriş ekranını göstermeden önce "Beni Hatırla"
/// tercihine ve mevcut (yerel) Supabase oturumuna bakarak üç yoldan birine
/// karar verir:
/// 1. `remember_me == false` → varsa mevcut oturum zorla kapatılır
///    (supabase_flutter oturumu kendiliğinden kalıcı tuttuğu için, aksi
///    halde kullanıcı "Beni Hatırla"yı hiç işaretlemese de bir sonraki
///    açılışta otomatik giriş yapılmış görünürdü), boş giriş formu gösterilir.
/// 2. `remember_me == true` ve yerelde bir oturum varsa → WelcomeBackScreen
///    (şifre sormadan "hoş geldin" ekranı; gerçek oturum geçerliliği o
///    ekranda, kullanıcı "Giriş Yap"a bastığında sunucuya sorularak
///    doğrulanır — burada sadece yerel varlığına bakılır).
/// 3. `remember_me == true` ama yerelde oturum yoksa (örn. daha önce başka
///    bir akıştan signOut olunmuş) → boş giriş formuna düşülür.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<Widget> _initialScreen = _resolveInitialScreen();

  Future<Widget> _resolveInitialScreen() async {
    final rememberMe = await LocalPrefsService.getRememberMe();

    if (!rememberMe) {
      if (SupabaseService.client.auth.currentSession != null) {
        await SupabaseService.client.auth.signOut();
      }
      return const LoginScreen();
    }

    final hasSession = SupabaseService.client.auth.currentSession != null;
    if (!hasSession) {
      return const LoginScreen();
    }

    final cachedFullName = await LocalPrefsService.getCachedFullName();
    return WelcomeBackScreen(cachedFullName: cachedFullName);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _initialScreen,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data!;
      },
    );
  }
}
