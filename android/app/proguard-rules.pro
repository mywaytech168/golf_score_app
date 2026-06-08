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

# SQLite / sqflite
-keep class io.flutter.plugins.sqflite.** { *; }

# JSON 序列化
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
