plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "local.baocode.mobile"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
    defaultConfig {
        // Preview and later updates keep BaoCodeX's independent install identity.
        applicationId = "juneix.baocodex"
        manifestPlaceholders["appLabel"] = "BaoCodeX"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    buildTypes {
        // No production signing credentials are created or checked in.
        // Local release builds must be signed explicitly before distribution.
        getByName("release") {
            isMinifyEnabled = false
            // Flutter 3.47's gradle plugin turns this on by default; it requires minification.
            isShrinkResources = false
        }
    }
    // -P arm64Only（tool/build_android.sh 发布时带）：只发 arm64，插件自带的
    // 别的架构的 .so 也不打进去；调试时模拟器要的 x86_64 照旧。
    if (project.hasProperty("arm64Only")) {
        packaging {
            jniLibs { excludes += listOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**") }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
