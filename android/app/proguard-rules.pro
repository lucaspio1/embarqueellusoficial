# ==============================================================================
# Regras ProGuard / R8 — Embarque Ellus
# Mantém classes chamadas via JNI/reflexão e permite ofuscação do restante (>25%)
# ==============================================================================

# Flutter Engine & Wrapper (sem manter deferredcomponents não usados)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.android.** { *; }
-keep class io.flutter.embedding.engine.FlutterJNI { *; }
-keep class io.flutter.embedding.engine.loader.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Core (referenciado por PlayStoreDeferredComponentManager do Flutter, mas opcional)
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn com.google.android.play.core.**

# TensorFlow Lite (usado pelo tflite_flutter via JNI)
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Google ML Kit / Play Services (JNI & Keep annotations)
-keep class com.google.mlkit.common.internal.** { *; }
-keep @com.google.android.gms.common.annotation.KeepName class *
-keepclassmembers class * {
    @com.google.android.gms.common.annotation.KeepName *;
}
-keep @com.google.android.apps.common.proguard.UsedBy* class *
-keepclassmembers class * {
    @com.google.android.apps.common.proguard.UsedBy* *;
}
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# Anotações opcionais de compilação (Guava / CameraX / OkHttp / Sentry)
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
-dontwarn io.sentry.**

# Preservar atributos necessários para stacktraces no Sentry / Play Console
-keepattributes SourceFile,LineNumberTable,Signature,InnerClasses,EnclosingMethod,*Annotation*
-renamesourcefileattribute SourceFile
