/// "2026-09-07T12:34:00+09:00" -> "2026/09/07 12:34". Extracted directly
/// from the string's own digits rather than via DateTime.parse + toLocal()
/// — DateTime.parse would convert to the *device's* timezone, but
/// createdAt is always JST from the API and should always display as JST
/// regardless of the device's own timezone.
///
/// Shared by KotonohaDetailScreen and KotonohaLeafPopup (STEP11-UI) so the
/// same parsing/formatting isn't duplicated across widgets.
String formatKotonohaDateTime(String iso8601) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})',
  ).firstMatch(iso8601);
  if (match == null) return iso8601;
  return '${match[1]}/${match[2]}/${match[3]} ${match[4]}:${match[5]}';
}
