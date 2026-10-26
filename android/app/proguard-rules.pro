# ==============================================================================
# Regras ProGuard / R8 — Embarque Ellus
# Mantém classes chamadas via JNI/reflexão e permite ofuscação do restante (>25%)
# ==============================================================================

# Flutter Engine & Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

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

# Preservar atributos necessários para stacktraces no Sentry / Play Console
-keepattributes SourceFile,LineNumberTable,Signature,InnerClasses,EnclosingMethod,*Annotation*
-renamesourcefileattribute SourceFile
