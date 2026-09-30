import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Banner ad shown above the map (docs/ads.md).
///
/// AdMob real-ID switch: release builds now use KOTONOHA's real production
/// banner ad unit; every other build (debug, profile) still uses Google's
/// official public test banner ad unit, matching AdMob's own guidance to
/// never serve production ad requests from a non-release build.
/// [kReleaseMode] is a compile-time constant (`flutter build/run
/// --release`), so this split is resolved at build time — a debug build
/// can never accidentally ship the production ad unit id, and vice versa.
/// Reserves the same height whether the ad is loading, loaded, or failed,
/// so the map/buttons below never shift.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  /// Google's official test banner ad unit ID for Android — see
  /// https://developers.google.com/admob/android/test-ads.
  static const _testBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  /// KOTONOHA's own production banner ad unit ID. Not a secret — an ad
  /// unit id is visible in every ad request the app makes and inside the
  /// built APK itself, so committing the real value here carries no
  /// confidentiality risk (same reasoning as the AdMob App ID in
  /// android/app/build.gradle.kts).
  static const _productionBannerAdUnitId = 'ca-app-pub-8340366887352312/9452113448';

  static String get _bannerAdUnitId =>
      kReleaseMode ? _productionBannerAdUnitId : _testBannerAdUnitId;

  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    final bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          // Never crash on a failed load — just keep the reserved space
          // blank (docs: 読み込み失敗時にアプリがクラッシュしないこと).
          ad.dispose();
        },
      ),
    );
    bannerAd.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bannerAd = _bannerAd;
    if (_isLoaded && bannerAd != null) {
      return SizedBox(
        width: double.infinity,
        height: bannerAd.size.height.toDouble(),
        child: Center(
          child: SizedBox(
            width: bannerAd.size.width.toDouble(),
            height: bannerAd.size.height.toDouble(),
            child: AdWidget(ad: bannerAd),
          ),
        ),
      );
    }

    // Loading, or failed: reserve the same slot AdSize.banner would use so
    // the layout below never shifts.
    return SizedBox(
      width: double.infinity,
      height: AdSize.banner.height.toDouble(),
    );
  }
}
