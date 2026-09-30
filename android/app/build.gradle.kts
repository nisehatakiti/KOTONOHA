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

// Google Mobile Ads (AdMob) App ID: unlike MAPS_API_KEY above, this is not
// a secret — it ships directly inside every built APK's own manifest,
// trivially readable via `aapt2 dump badging` (or by anyone who installs
// the app), so there is no confidentiality reason to keep the real one out
// of git, and no local.properties override — a stale/forgotten override
// value could otherwise silently clobber both build types' own defaults
// identically, defeating the whole point of the split below. debug always
// gets Google's official public test App ID (AdMob's own guidance: a
// development build must never serve production ad requests — see
// https://developers.google.com/admob/android/test-ads); release always
// gets KOTONOHA's real production App ID.
val testAdMobAppId = "ca-app-pub-3940256099942544~3347511713"
val productionAdMobAppId = "ca-app-pub-8340366887352312~8046060256"

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
        // Per-build-type AdMob App ID defaults (test for debug, production
        // for release) are set explicitly on each buildType below — this
        // default only exists as a safety net for some future buildType
        // that forgets to set its own.
        manifestPlaceholders["ADMOB_APP_ID"] = testAdMobAppId
    }

    buildTypes {
        debug {
            manifestPlaceholders["ADMOB_APP_ID"] = testAdMobAppId
        }
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
            manifestPlaceholders["ADMOB_APP_ID"] = productionAdMobAppId
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
