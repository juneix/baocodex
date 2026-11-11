pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val local = file("local.properties")
        require(local.exists()) {
            "Missing android/local.properties. Run tool/prepare_android.ps1 with -FlutterSdk and -AndroidSdk."
        }
        local.inputStream().use { properties.load(it) }
        properties.getProperty("flutter.sdk") ?: error("flutter.sdk is not set")
    }
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
