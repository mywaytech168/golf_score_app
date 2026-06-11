import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:golf_score_app/main.dart';
import 'package:golf_score_app/providers/locale_provider.dart';

void main() {
  testWidgets('應用啟動後顯示 MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(localeProvider: LocaleProvider()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
