// android/app/build.gradle.kts
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")                    // keep ONE kotlin plugin
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val localProperties = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) load(f.inputStream())
}
val flutterVersionCode = (localProperties.getProperty("flutter.versionCode") ?: "1").toInt()
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0"

// NOTE: our CI writes key.properties to android/key.properties
val keystoreProperties = Properties().apply {
    val f = rootProject.file("android/key.properties")
    if (f.exists()) load(f.inputStream())
}

android {
    namespace = "com.krysta.hommie"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.krysta.hommie"
        // KTS syntax (was: minSdkVersion flutter.minSdkVersion)
        // If you use Firebase, many plugins need at least 23:
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = 36
        versionCode = flutterVersionCode
        versionName = flutterVersionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("storeFile")) {
                storeFile = file(keystoreProperties["storeFile"].toString())
                storePassword = keystoreProperties["storePassword"].toString()
                keyAlias = keystoreProperties["keyAlias"].toString()
                keyPassword = keystoreProperties["keyPassword"].toString()
            }
        }
    }

    buildTypes {
        getByName("debug") { /* debug options if needed */ }
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

flutter { source = "../.." }

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
    // kotlin stdlib is added automatically by the plugin; no need to add it manually
}
