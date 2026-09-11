import 'package:flutter/material.dart';

import '../models/kotonoha_item.dart';
import '../screens/kotonoha_detail_screen.dart';
import '../services/kotonoha_api_service.dart';
import 'kotonoha_tile.dart';

/// Bottom sheet shown after tapping a leaf marker (STEP10-A): fetches and
/// displays the 言の葉 clustered at that pin's location as a photo-first
/// tile grid (docs/ui.md section 4: 同一地点・近接地点のタイル一覧).
///
/// Owns its own fetch/loading/retry lifecycle — KotonohaMap only ever
/// reports "this id was tapped" and never talks to the API itself
/// (see KotonohaMap.onLeafTap).
class KotonohaTileListSheet extends StatefulWidget {
  const KotonohaTileListSheet({super.key, required this.id, this.apiService});

  final String id;

  // Injectable so widget tests can supply a fake instead of hitting the
  // real network; defaults to the real service otherwise.
  final KotonohaApiService? apiService;

  @override
  State<KotonohaTileListSheet> createState() => _KotonohaTileListSheetState();
}

class _KotonohaTileListSheetState extends State<KotonohaTileListSheet> {
  late final _apiService = widget.apiService ?? KotonohaApiService();
  late Future<List<KotonohaItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<KotonohaItem>> _fetch() {
    return _apiService.fetchKotonohaCluster(int.parse(widget.id));
  }

  void _retry() {
    setState(() {
      _future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return SafeArea(
          top: false,
          child: FutureBuilder<List<KotonohaItem>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                final error = snapshot.error;
                // A 404 (not found / already deleted) is empty data, not a
                // transient failure — no retry button for it (STEP10-A
                // spec section 24 vs section 23).
                if (error is KotonohaApiException &&
                    error.reason == KotonohaApiFailureReason.notFound) {
                  return const _MessageState(
                    message: 'この言の葉は見つかりませんでした',
                  );
                }
                return _MessageState(
                  message: '読み込みに失敗しました',
                  onRetry: _retry,
                );
              }

              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return const _MessageState(
                  message: 'この言の葉は見つかりませんでした',
                );
              }

              return GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(8),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.75,
                    ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return KotonohaTile(
                    item: item,
                    // Pushed on top of this sheet's own route, so the
                    // system/app-bar back button returns here — the tile
                    // list — rather than all the way to the map
                    // (STEP10-B section 3). A successful connect (STEP11)
                    // pops back with `true`, so the list is re-fetched and
                    // the new comment shows up without a manual refresh.
                    onTap: () async {
                      final connected = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => KotonohaDetailScreen(item: item),
                        ),
                      );
                      if (connected == true) _retry();
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('再試行')),
          ],
        ],
      ),
    );
  }
}
