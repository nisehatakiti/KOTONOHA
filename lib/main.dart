import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app/kotonoha_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fire-and-forget: ad SDK init must never delay or block app startup, and
  // a failure here must not prevent the rest of the app (installation_id,
  // Google Map, current location) from starting normally.
  unawaited(_initializeMobileAds());
  runApp(const KotonohaApp());
}

Future<void> _initializeMobileAds() async {
  try {
    await MobileAds.instance.initialize();
  } catch (_) {
    // Ignored: the ad banner simply stays unloaded (see AdBanner) if the
    // Mobile Ads SDK fails to initialize.
  }
}
