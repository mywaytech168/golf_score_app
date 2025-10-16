// 基本的 Flutter Widget 測試，確認應用入口可以正常建立 UI。

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:golf_score_app/main.dart';
import 'package:golf_score_app/pages/login_page.dart';

void main() {
  testWidgets('應用啟動後顯示登入頁', (WidgetTester tester) async {
    // ---------- 測試前置 ----------
    // 建立空的鏡頭清單，模擬測試環境沒有實體相機。
    const List<CameraDescription> fakeCameras = <CameraDescription>[];

    // ---------- 測試步驟 ----------
    await tester.pumpWidget(
      const MyApp(
        initialCameras: fakeCameras,
        initialCameraError: null,
      ),
    );
    await tester.pumpAndSettle();

    // ---------- 驗證結果 ----------
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
