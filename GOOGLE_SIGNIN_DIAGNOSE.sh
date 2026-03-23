#!/bin/bash
# Google Sign-In Android 诊断脚本

echo "============================================"
echo "Google Sign-In Android 诊断报告"
echo "============================================"
echo ""

# 1. 检查 Package Name
echo "1️⃣ 检查 Package Name"
PACKAGE_NAME=$(grep 'applicationId' android/app/build.gradle.kts | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "Package Name: $PACKAGE_NAME"
echo ""

# 2. 检查 build.gradle.kts 配置
echo "2️⃣ 检查 build.gradle.kts 中的签名配置"
if grep -q "signingConfigs" android/app/build.gradle.kts; then
    echo "✅ 找到签名配置"
else
    echo "⚠️ 未找到签名配置"
fi
echo ""

# 3. 检查 AndroidManifest.xml
echo "3️⃣ 检查 AndroidManifest.xml 中的 Google Play Services 配置"
if grep -q "com.google.android.gms.version" android/app/src/main/AndroidManifest.xml; then
    echo "✅ 找到 Google Play Services 配置"
else
    echo "⚠️ 未找到 Google Play Services 配置"
fi
echo ""

# 4. 获取 SHA-1 指纹
echo "4️⃣ 获取 Debug SHA-1 指纹"
echo "运行: ./gradlew signingReport"
echo ""

# 5. 所需的检查清单
echo "5️⃣ 配置检查清单"
echo "[ ] Android Client ID 在 login_page.dart 中正确配置"
echo "[ ] SHA-1 指纹已添加到 Google Cloud Console"
echo "[ ] Package name 与 Google Cloud 中的一致"
echo "[ ] google_sign_in 依赖已添加到 pubspec.yaml"
echo ""

echo "============================================"
echo "下一步:"
echo "1. 运行: cd android && ./gradlew signingReport"
echo "2. 复制 SHA1 值"
echo "3. 打开 Google Cloud Console"
echo "4. 找到 Android Client ID"
echo "5. 添加 SHA-1 指纹"
echo "6. 保存并重新构建应用"
echo "============================================"
