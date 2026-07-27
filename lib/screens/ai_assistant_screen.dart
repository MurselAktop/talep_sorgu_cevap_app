import 'package:flutter/material.dart';

import '../widgets/ai_assistant_chat.dart';
import '../widgets/app_nav_route.dart';
import '../widgets/navigation_shell.dart';
import 'request_create_screen.dart';

/// Arıza Talep Asistanı — sidebar/drawer'dan ("Arıza Asistanı" öğesi) veya
/// Ana ekrandaki rozet ikonundan (bkz. `home_screen.dart`) ulaşılan tam
/// ekran sohbet arayüzü. Aynı [AiAssistantChat] gövdesi, Ana ekrandaki
/// `BottomSheet` ile BİREBİR aynı davranışı (çok turlu sohbet, birim önerisi,
/// "talep oluştur" aksiyonu) gösterir — burada sadece sabit bir sayfa
/// içinde, `BottomSheet`e sıkışmadan daha ferah kullanılabiliyor.
class AiAssistantScreen extends StatelessWidget {
  const AiAssistantScreen({super.key});

  void _goToCreateRequest(BuildContext context, int departmentId, String lastUserText) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RequestCreateScreen(
          initialDescription: lastUserText,
          initialDepartmentId: departmentId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavigationShell(
      currentRoute: AppNavRoute.aiAssistant,
      title: 'Arıza Asistanı',
      body: AiAssistantChat(
        onDepartmentAction: (departmentId, lastUserText) =>
            _goToCreateRequest(context, departmentId, lastUserText),
      ),
    );
  }
}
