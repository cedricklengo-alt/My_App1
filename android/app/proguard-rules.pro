# 🔒 MboteCall — règles R8 (release)
# Flutter / JNI
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
# Kotlin coroutines
-keep class kotlinx.coroutines.** { *; }
# WebRTC (flutter_webrtc)
-keep class org.webrtc.** { *; }
-keep class io.flutter.plugins.webrtc.** { *; }
# Firebase / FCM
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
# Gson / modèles si sérialisation JSON
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn org.webrtc.**
