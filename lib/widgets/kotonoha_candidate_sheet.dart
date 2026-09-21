import 'package:flutter/material.dart';

import '../services/kotonoha_api_service.dart';
import '../utils/kotonoha_format.dart';

/// Shown via `showModalBottomSheet<String>` when a tapped leaf marker has
/// more than one 言の葉 grouped at/near it (see KotonohaMap._handleMarkerTap,
/// KotonohaMap.kNearbyLeafGroupRadiusMeters) — lets the user pick which one
/// to open instead of KotonohaMap silently guessing based on whichever
/// marker Google Maps' own hit-testing happened to resolve the tap to.
///
/// Purely a *picker*: each row shows just enough to tell candidates apart
/// (最初の言葉 + date/time, docs section 5 — "詳細情報をすべて表示する必要
/// はない"), never a photo thumbnail (this app's other list-style surface,
/// KotonohaTile, is photo-first, but that reads as a bigger design lift
/// than this compact picker calls for — kept out per docs section 5's own
/// "現在のデザインと整合しない場合は無理に追加しない").
///
/// `GET /api/kotonoha/nearby` (KotonohaMap's own [KotonohaApiService.
/// fetchNearby]) only ever returns id/lat/lng, never comment/date — so
/// this widget fetches each candidate's own summary via
/// [KotonohaApiService.fetchKotonohaRootDetail] (comment/createdAt are
/// always present in that response, regardless of the caller's distance —
/// see KotonohaRootSummary) once it's shown, rather than KotonohaMap
/// needing to pre-fetch full summaries for every visible pin up front.
///
/// Resolves (via `Navigator.pop(context, id)`) with the tapped candidate's
/// own [String] id — never an index — so KotonohaMap can open exactly the
/// 言の葉 the user actually chose regardless of fetch-completion order.
class KotonohaCandidateSheet extends StatefulWidget {
  const KotonohaCandidateSheet({
    super.key,
    required this.candidateIds,
    this.apiService,
  });

  /// The ids to offer, already narrowed down to "at/near the tapped spot"
  /// by the caller (KotonohaMap) — this widget does no distance filtering
  /// of its own.
  final List<String> candidateIds;

  // Injectable so widget tests can supply a fake instead of hitting the
  // real network; defaults to the real service otherwise (the same
  // pattern used throughout this app's screens).
  final KotonohaApiService? apiService;

  @override
  State<KotonohaCandidateSheet> createState() => _KotonohaCandidateSheetState();
}

class _KotonohaCandidateSheetState extends State<KotonohaCandidateSheet> {
  late final _apiService = widget.apiService ?? KotonohaApiService();
  late final Future<List<_Candidate>> _future = _loadAll();

  Future<List<_Candidate>> _loadAll() {
    // Order preserved (Future.wait keeps input order in its result list),
    // so this list lines up 1:1 with widget.candidateIds regardless of
    // which network call actually finishes first.
    return Future.wait(widget.candidateIds.map(_loadOne));
  }

  Future<_Candidate> _loadOne(String id) async {
    try {
      final detail = await _apiService.fetchKotonohaRootDetail(id: int.parse(id));
      return _Candidate(
        id: id,
        comment: detail.root.comment,
        createdAt: detail.root.createdAt,
      );
    } catch (_) {
      // A single candidate failing to load (deleted between the nearby
      // fetch and now, a transient network error, ...) shouldn't block the
      // rest of the sheet — still offer it, just without a preview.
      return _Candidate(id: id, comment: null, createdAt: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Real-device-consistent design pass: matches LeafDecoratedSection's
    // own wash color (kotonoha_detail_screen.dart /
    // kotonoha_words_screen.dart) rather than a plain white sheet — this
    // is the same "candidates at one spot" concept as those screens, not a
    // new, unrelated UI.
    const washColor = Color(0xFFF3F9EE);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // 候補が少ない場合は必要以上に大きくしない: ListView below is
        // shrinkWrap: true, so with few candidates this whole sheet sizes
        // down to their actual content height; this cap only kicks in —
        // and turns the list scrollable — once candidates are numerous
        // enough to need it (docs section 11).
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(
                'この場所の言の葉',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            Flexible(
              child: FutureBuilder<List<_Candidate>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final candidates = snapshot.data ?? const [];
                  return ListView.separated(
                    // See the maxHeight comment above — this is what lets
                    // the sheet size to content when small and scroll
                    // internally once candidates exceed that cap.
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: candidates.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final candidate = candidates[index];
                      return _CandidateCard(
                        candidate: candidate,
                        washColor: washColor,
                        // Captures this row's own id, not the index — the
                        // list is rebuilt from the same _future each time,
                        // so this always matches the row the user actually
                        // tapped (docs section 6: インデックス依存の不具合
                        // を避ける).
                        onTap: () => Navigator.of(context).pop(candidate.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Candidate {
  const _Candidate({required this.id, required this.comment, required this.createdAt});

  final String id;
  final String? comment;
  final String? createdAt;
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.washColor,
    required this.onTap,
  });

  final _Candidate candidate;
  final Color washColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: washColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.comment ?? '読み込みに失敗しました',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    if (candidate.createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        formatKotonohaDateTime(candidate.createdAt!),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }
}
