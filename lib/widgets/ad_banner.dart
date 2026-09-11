import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Banner ad shown above the map (docs/ads.md).
///
/// STEP9: always uses Google's official public test banner ad unit —
/// never a real production ad unit. Reserves the same height whether the
/// ad is loading, loaded, or failed, so the map/buttons below never shift.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  /// Google's official test banner ad unit ID for Android — see
  /// https://developers.google.com/admob/android/test-ads. Do not replace
  /// with a real production ad unit ID in this STEP.
  static const _testBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    final bannerAd = BannerAd(
      adUnitId: _testBannerAdUnitId,
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
