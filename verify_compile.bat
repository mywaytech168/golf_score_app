@echo off
REM 並行優化編譯驗證

cd /d D:\Projects\golf_score_app

echo ============================================
echo  Flutter 並行優化驗證
echo ============================================

echo.
echo [步驟 1] Dart 分析...
call d:\flutter\bin\flutter.bat analyze lib\services\video_analysis_service.dart

if %ERRORLEVEL% NEQ 0 (
    echo ❌ 分析失敗
    exit /b 1
)

echo.
echo [步驟 2] 清理...
call d:\flutter\bin\flutter.bat clean

echo.
echo [步驟 3] 獲取依賴...
call d:\flutter\bin\flutter.bat pub get

echo.
echo [步驟 4] 編譯 APK (Debug)...
call d:\flutter\bin\flutter.bat build apk --debug

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ✅ 編譯成功！
    echo APK 位置: build\app\outputs\flutter-apk\app-debug.apk
) else (
    echo.
    echo ❌ 編譯失敗
)

exit /b %ERRORLEVEL%
