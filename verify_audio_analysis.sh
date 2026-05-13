#!/bin/bash
# 音频分析快速验证脚本

RECORDING_DIR="1778637922771"
APP_PACKAGE="com.example.golf_score_app"
APP_DATA_DIR="/data/data/$APP_PACKAGE"

echo "🔍 音频分析验证"
echo "======================================"
echo "📁 录制目录: $RECORDING_DIR"
echo ""

# 检查 CSV 文件
echo "📊 CSV 文件检查:"
adb shell run-as $APP_PACKAGE ls -lh app_flutter/golf_recordings/$RECORDING_DIR/audio_features.csv 2>&1
if [ $? -eq 0 ]; then
    echo "   ✅ 文件存在"
    echo ""
    echo "   📈 CSV 内容预览 (前 5 行):"
    adb shell run-as $APP_PACKAGE head -5 app_flutter/golf_recordings/$RECORDING_DIR/audio_features.csv
else
    echo "   ❌ 文件不存在"
fi

echo ""
echo "======================================"

# 检查 TXT 文件
echo "📋 TXT 文件检查:"
adb shell run-as $APP_PACKAGE ls -lh app_flutter/golf_recordings/$RECORDING_DIR/audio_analysis.txt 2>&1
if [ $? -eq 0 ]; then
    echo "   ✅ 文件存在"
    echo ""
    echo "   📄 TXT 内容预览:"
    adb shell run-as $APP_PACKAGE head -20 app_flutter/golf_recordings/$RECORDING_DIR/audio_analysis.txt
else
    echo "   ❌ 文件不存在"
fi

echo ""
echo "======================================"

# 查看所有文件
echo "📁 完整的录制目录内容:"
adb shell run-as $APP_PACKAGE ls -lh app_flutter/golf_recordings/$RECORDING_DIR/

echo ""
echo "✅ 验证完成"
