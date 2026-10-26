import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Assinatura de release: android/key.properties + android/app/key.jks.
// No GitHub Actions os dois são criados a partir dos secrets do repositório.
// Sem eles (ex.: build local de teste) o release sai assinado com a chave debug.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val temChaveRelease = keystoreProperties.getProperty("storeFile")?.let { file(it).exists() } == true

android {
    namespace = "br.com.embarqueellus"

    // ✅ Atualizado para suportar o mobile_scanner e alinhamento de 16 KB (NDK r28)
    compileSdk = 36
    ndkVersion = "28.0.13004108"

    defaultConfig {
        applicationId = "br.com.embarqueellus"
        // ✅ mobile_scanner exige no mínimo API 23 (Android 6.0)
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        // Vêm do pubspec.yaml (version: X.Y.Z+N) ou de --build-name/--build-number
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Mantém compatibilidade com Flutter
        multiDexEnabled = true

        ndk {
            // Dispositivos Android modernos 64-bit e suporte a páginas de 16 KB
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    packaging {
        jniLibs {
            // Alinha bibliotecas nativas (.so) não comprimidas em limites de 16 KB (AGP 8.5+)
            useLegacyPackaging = false
        }
    }

    signingConfigs {
        if (temChaveRelease) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName(if (temChaveRelease) "release" else "debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 🔹 Suporte a multidex (caso o app cresça)
    implementation("androidx.multidex:multidex:2.0.1")

    // 🔹 CameraX (usado pelo mobile_scanner)
    implementation("androidx.camera:camera-core:1.5.0")
    implementation("androidx.camera:camera-camera2:1.5.0")
    implementation("androidx.camera:camera-lifecycle:1.5.0")
    implementation("androidx.camera:camera-view:1.5.0")

    // 🔹 ML Kit para detecção facial nativa
    implementation("com.google.mlkit:face-detection:16.1.6")

    // 🔹 ExifInterface para correção de rotação EXIF
    implementation("androidx.exifinterface:exifinterface:1.3.7")
}
