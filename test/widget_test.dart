import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:talep_sorgu_cevap_app/main.dart';

void main() {
  testWidgets('HomePage başlığı görünüyor', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.text('Talep ve Şikâyet Yönetim Sistemi'), findsOneWidget);
  });
}
