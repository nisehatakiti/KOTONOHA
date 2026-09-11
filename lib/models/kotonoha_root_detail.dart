/// A Root post as returned by `GET /api/kotonoha/{id}` (STEP11-UI (A)/(B)
/// fix). Fields other than [id]/[comment]/[createdAt] are only present
/// when the server determined the caller is within 5m — never included
/// (not just hidden) otherwise, so they're nullable here rather than on
/// [KotonohaItem], which always has all of them.
class KotonohaRootSummary {
  const KotonohaRootSummary({
    required this.id,
    required this.comment,
    required this.createdAt,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.imageUrl,
  });

  final String id;
  final String comment;
  final String createdAt;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final String? imageUrl;
}

/// A connect post as listed under a Root's `connections` (STEP11-UI).
/// Only ever present when the Root summary itself is "near" — connect
/// posts have no coordinates/photo of their own to expose here.
class KotonohaConnection {
  const KotonohaConnection({
    required this.id,
    required this.parentId,
    required this.comment,
    required this.createdAt,
  });

  final String id;
  final String parentId;
  final String comment;
  final String createdAt;
}

/// The full `GET /api/kotonoha/{id}` response: a Root, plus whatever
/// connect posts the server decided to include alongside it (empty when
/// the caller wasn't within 5m — never a best-effort client-side guess).
class KotonohaRootDetail {
  const KotonohaRootDetail({
    required this.root,
    this.connections = const [],
  });

  final KotonohaRootSummary root;
  final List<KotonohaConnection> connections;
}
