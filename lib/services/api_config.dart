/// KOTONOHA-API base URL (see the separate KOTONOHA-API repository).
///
/// Production is confirmed: `https://api.hatakiti.com`. `KotonohaApiService`
/// appends `/api/kotonoha` to this, giving the real endpoint
/// `https://api.hatakiti.com/api/kotonoha` (extension-less; the server
/// rewrites it internally to kotonoha.php — see KOTONOHA-API/README.md).
///
/// For local development against a PHP dev server instead, override at
/// build/run time rather than editing this file:
///
/// ```
/// flutter run --dart-define=KOTONOHA_API_BASE_URL=http://10.0.2.2:8000
/// ```
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'KOTONOHA_API_BASE_URL',
    defaultValue: 'https://api.hatakiti.com',
  );
}
