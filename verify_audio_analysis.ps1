# 音频分析快速验证脚本 (PowerShell)
# 用法: .\verify_audio_analysis.ps1

$RecordingDir = "1778637922771"
$AppPackage = "com.example.golf_score_app"

Write-Host "🔍 音频分析验证" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Gray
Write-Host "📁 录制目录: $RecordingDir" -ForegroundColor Yellow
Write-Host ""

# 检查 CSV 文件
Write-Host "📊 CSV 文件检查:" -ForegroundColor Cyan
$csvCheck = adb shell run-as $AppPackage ls -lh app_flutter/golf_recordings/$RecordingDir/audio_features.csv 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ 文件存在" -ForegroundColor Green
    Write-Host ""
    Write-Host "   📈 CSV 内容预览 (前 5 行):" -ForegroundColor Yellow
    adb shell run-as $AppPackage head -5 app_flutter/golf_recordings/$RecordingDir/audio_features.csv
} else {
    Write-Host "   ❌ 文件不存在" -ForegroundColor Red
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Gray
Write-Host ""

# 检查 TXT 文件
Write-Host "📋 TXT 文件检查:" -ForegroundColor Cyan
$txtCheck = adb shell run-as $AppPackage ls -lh app_flutter/golf_recordings/$RecordingDir/audio_analysis.txt 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ 文件存在" -ForegroundColor Green
    Write-Host ""
    Write-Host "   📄 TXT 内容预览:" -ForegroundColor Yellow
    adb shell run-as $AppPackage head -20 app_flutter/golf_recordings/$RecordingDir/audio_analysis.txt
} else {
    Write-Host "   ❌ 文件不存在" -ForegroundColor Red
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Gray
Write-Host ""

# 查看所有文件
Write-Host "📁 完整的录制目录内容:" -ForegroundColor Cyan
adb shell run-as $AppPackage ls -lh app_flutter/golf_recordings/$RecordingDir/

Write-Host ""
Write-Host "✅ 验证完成" -ForegroundColor Green
