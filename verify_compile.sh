#!/bin/bash
# 快速編譯驗證腳本

cd /d D:\Projects\golf_score_app

echo "=== Flutter 狀態檢查 ==="
echo "版本："
d:\flutter\bin\flutter.bat --version

echo ""
echo "=== Dart 分析 ==="
d:\flutter\bin\flutter.bat analyze lib/services/video_analysis_service.dart

echo ""
echo "=== 編譯 APK ==="
d:\flutter\bin\flutter.bat build apk --debug --verbose 2>&1 | tail -100
