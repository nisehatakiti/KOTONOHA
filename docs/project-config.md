# KOTONOHA — Project Configuration v0.1

## Application ID

Flutter / Android application identifier:

`com.nisehatakiti.kotonoha`

This identifier is the canonical application ID for KOTONOHA and should not be changed after release.

## Advertising

KOTONOHA uses Google AdMob for the banner advertisement displayed above the map.

- AdMob account: prepared
- Ad format: banner
- Development: use test advertisements
- Production: use the production ad unit only after release configuration is complete
- Advertising categories that may conflict with the KOTONOHA concept should be filtered where AdMob settings permit.

AdMob App ID and Ad Unit ID are environment/configuration values and must not be hard-coded into the general application specification.
