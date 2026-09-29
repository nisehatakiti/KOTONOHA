import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google Maps API key (STEP5): read from the git-ignored local.properties
// instead of hardcoding it, so it never ends up in source control. Empty
// string is a valid default — the app still builds, but the map tiles
// won't load until a real key is set (see android/local.properties).
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { stream -> localProperties.load(stream) }
}
val mapsApiKey: String = localProperties.getProperty("MAPS_API_KEY", "")

// Google Mobile Ads (AdMob) App ID (STEP9): same pattern as MAPS_API_KEY
// above — read from the git-ignored local.properties, never hardcoded.
val adMobAppId: String = localProperties.getProperty("ADMOB_APP_ID", "")

android {
    namespace = "com.nisehatakiti.kotonoha"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nisehatakiti.kotonoha"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        manifestPlaceholders["ADMOB_APP_ID"] = adMobAppId
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Real-device fix: R8 minification turned out to be enabled by
            // this AGP version's own default even without this project
            // ever setting isMinifyEnabled explicitly — the release build
            // crashed on launch until proguard-rules.pro's Room/WorkManager
            // keep rules were added (see that file's own comment for the
            // full logcat-confirmed root cause). Explicitly declaring both
            // here now, rather than leaving it implicit, so the proguard
            // file's keep rules are actually applied.
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
