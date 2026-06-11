# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Play Core (deferred components)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Apache Tika (javax.xml)
-dontwarn javax.xml.stream.**
-dontwarn org.apache.tika.**

# Google ML Kit
-keep class com.google.mlkit.** { *; }

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }

# In-App Purchase
-keep class com.android.billingclient.** { *; }

# Google Sign In
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# TFLite
-keep class org.tensorflow.** { *; }

# MediaPipe Tasks（PoseLandmarker 走 JNI，類名不可混淆）
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# 保留所有含 native 方法的類別與方法名（golf_native.so JNI 綁定）
-keepclasseswithmembernames class * {
    native <methods>;
}

# SQLite / sqflite
-keep class io.flutter.plugins.sqflite.** { *; }

# JSON 序列化
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions

# R8 missing classes: AutoValue / JavaPoet annotation processor only
# javax.lang.model 是 Java 編譯期 API，Android runtime 不提供；實際 app 執行通常不會用到
-dontwarn javax.lang.model.**
-dontwarn autovalue.shaded.com.squareup.javapoet$.$**
-dontwarn com.google.auto.value.processor.**