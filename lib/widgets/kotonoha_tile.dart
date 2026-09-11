import 'package:flutter/material.dart';

import '../models/kotonoha_item.dart';

/// A single photo+comment tile in the tap-a-pin tile list (STEP10-A,
/// docs/ui.md section 4: 写真を中心としたタイル状の一覧).
///
/// Tapping does nothing yet — the detail view is a later STEP — but
/// [onTap] is already wired so adding navigation later only means passing
/// a callback here, not restructuring this widget.
class KotonohaTile extends StatelessWidget {
  const KotonohaTile({super.key, required this.item, this.onTap});

  final KotonohaItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.imageUrl;

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl == null
                  ? _placeholder()
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return _placeholder(loading: true);
                      },
                      errorBuilder: (context, error, stackTrace) =>
                          _placeholder(failed: true),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.comment,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            _shortDate(item.createdAt),
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _placeholder({bool loading = false, bool failed = false}) {
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : failed
          ? Icon(Icons.broken_image, color: Colors.grey.shade600)
          : null,
    );
  }

  /// "2026-09-06T19:00:00+09:00" -> "09-06 19:00". Extracted directly from
  /// the string's own digits rather than via DateTime.parse — that would
  /// convert to the *device's* timezone, but createdAt is always JST from
  /// the API and should always display as JST (STEP10-B fix; see the same
  /// note on KotonohaDetailScreen._formatCreatedAt).
  String _shortDate(String iso8601) {
    final match = RegExp(
      r'^\d{4}-(\d{2})-(\d{2})T(\d{2}):(\d{2})',
    ).firstMatch(iso8601);
    if (match == null) return iso8601;
    return '${match[1]}-${match[2]} ${match[3]}:${match[4]}';
  }
}
