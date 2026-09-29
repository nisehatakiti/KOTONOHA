# Real-device fix: release build crashed on launch (FATAL EXCEPTION at app
# process start, before any Flutter/Dart code runs — confirmed via
# `adb logcat`, not guessed) with:
#
#   Unable to get provider androidx.startup.InitializationProvider:
#   RuntimeException: Failed to create an instance of
#   androidx.work.impl.WorkDatabase
#
# Root cause: google_mobile_ads (AdMob) transitively depends on
# com.google.android.gms:play-services-ads-api, which depends on
# androidx.work:work-runtime (confirmed via that artifact's own POM in the
# Gradle cache — this app never uses WorkManager directly). WorkManager's
# own androidx.startup Initializer (a ContentProvider, so it runs before
# Application.onCreate — this is why the crash happens before Dart's own
# main.dart try/catch around MobileAds.instance.initialize() can ever run)
# builds a Room database (WorkDatabase) at app startup. Room only finds its
# generated `*_Impl` implementation classes by name at runtime — R8 can't
# see that reflective lookup via static analysis, so without an explicit
# keep rule it renames/strips them, and the Room database fails to build.
#
# This project has no minifyEnabled set explicitly and no proguard-rules.pro
# existed before this fix — R8 minification/shrinking turned out to be
# enabled by AGP's own current default regardless, so this file (and
# wiring it into android/app/build.gradle.kts's release buildType) is now
# required rather than optional.
#
# Standard, official Room-recommended keep rules (protects any current or
# future Room-based transitive dependency the same way, not just
# WorkManager specifically) — deliberately scoped to Room's own generated
# classes only, not a blanket R8 disable.
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Database class *
-keep class **_Impl { *; }
