import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kotonoha/models/kotonoha_item.dart';
import 'package:kotonoha/models/kotonoha_root_detail.dart';
import 'package:kotonoha/models/location_point.dart';
import 'package:kotonoha/screens/kotonoha_detail_screen.dart';
import 'package:kotonoha/screens/kotonoha_words_screen.dart';
import 'package:kotonoha/services/location_service.dart';
import 'package:kotonoha/widgets/ad_banner.dart';

/// Real-device UI pass: "言の葉をひらく" now opens [KotonohaWordsScreen]
/// first — AC-01..AC-05.
class _FakeLocationService implements LocationService {
  _FakeLocationService.success()
    : _point = const LocationPoint(latitude: 35.0, longitude: 139.0, accuracy: 5),
      _error = null;

  final LocationPoint? _point;
  final LocationServiceException? _error;

  @override
  Future<LocationPoint> getCurrentLocation() async {
    if (_error != null) throw _error;
    return _point!;
  }
}

const _item = KotonohaItem(
  id: '6',
  latitude: 35.0,
  longitude: 139.0,
  accuracy: 8.5,
  imageUrl: 'https://example.test/media/kotonoha/a.jpg',
  comment: '今日の空はきれい',
  createdAt: '2026-09-07T12:34:00+09:00',
);

const _connections = [
  KotonohaConnection(
    id: '10',
    parentId: '6',
    comment: '空がすごく青い',
    createdAt: '2026-09-07T12:40:00+09:00',
  ),
  KotonohaConnection(
    id: '11',
    parentId: '6',
    comment: 'またここに来たい',
    createdAt: '2026-09-07T12:45:00+09:00',
  ),
  KotonohaConnection(
    id: '12',
    parentId: '6',
    comment: '4件目でも全部表示される',
    createdAt: '2026-09-07T12:50:00+09:00',
  ),
];

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets(
    'AC-01/AC-05: shows a small fixed photo header plus the first word '
    '(the Root comment) and its date below it',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          KotonohaWordsScreen(
            item: _item,
            locationService: _FakeLocationService.success(),
          ),
        ),
      );

      expect(find.text('今日の空はきれい'), findsOneWidget);
      expect(find.text('2026/09/07 12:34'), findsOneWidget);
      // The photo header itself — not the large KotonohaDetailScreen,
      // which is only reached by tapping it.
      expect(find.byType(KotonohaDetailScreen), findsNothing);
    },
  );

  testWidgets(
    'shows every connected word (unlike the map popup\'s capped 3-item '
    'preview, this dedicated screen has room for all of them)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          KotonohaWordsScreen(
            item: _item,
            connectedItems: _connections,
            locationService: _FakeLocationService.success(),
          ),
        ),
      );

      expect(find.text('空がすごく青い'), findsOneWidget);
      expect(find.text('またここに来たい'), findsOneWidget);
      expect(find.text('4件目でも全部表示される'), findsOneWidget);
    },
  );

  testWidgets(
    'AC-02/AC-03: the photo header sits outside the scrollable words '
    'area — a Column sibling of the SingleChildScrollView, not inside it '
    '— so scrolling the words can never move the photo',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          KotonohaWordsScreen(
            item: _item,
            connectedItems: _connections,
            locationService: _FakeLocationService.success(),
          ),
        ),
      );

      // Distinct from the screen's own decorative leaf-motif background
      // image (real-device UI pass: LeafDecoratedSection), which is also
      // legitimately an Image now — same reasoning as
      // kotonoha_detail_screen_test.dart's own photo finder.
      final photoFinder = find.byWidgetPredicate(
        (w) => w is Image && w.image is NetworkImage,
      );
      final scrollViewFinder = find.byType(SingleChildScrollView);
      expect(photoFinder, findsOneWidget);
      expect(scrollViewFinder, findsOneWidget);

      // The photo must NOT be a descendant of the scroll view.
      expect(
        find.descendant(of: scrollViewFinder, matching: photoFinder),
        findsNothing,
      );
    },
  );

  testWidgets(
    'AC-04: tapping the small photo opens KotonohaDetailScreen (the '
    'existing large-photo screen, reused as-is) showing the same first '
    'word',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          KotonohaWordsScreen(
            item: _item,
            locationService: _FakeLocationService.success(),
          ),
        ),
      );

      await tester.tap(
        find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage),
      );
      await tester.pumpAndSettle();

      expect(find.byType(KotonohaDetailScreen), findsOneWidget);
      // AC-05 (on the large-photo screen itself, unchanged): the first
      // word is shown there too.
      expect(find.text('今日の空はきれい'), findsOneWidget);
    },
  );

  testWidgets(
    'real-device UI pass: shows the same ad banner and leaf-motif '
    'background used on the large-photo KotonohaDetailScreen',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          KotonohaWordsScreen(
            item: _item,
            locationService: _FakeLocationService.success(),
          ),
        ),
      );

      expect(find.byType(AdBanner), findsOneWidget);
      // The decorative leaf-motif background image — an asset image,
      // distinct from the Root's own network photo.
      expect(
        find.byWidgetPredicate((w) => w is Image && w.image is AssetImage),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '非常に重要: the small photo scales down preserving its source aspect '
    'ratio (BoxFit.contain) rather than cropping it to fill the header '
    '(BoxFit.cover)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          KotonohaWordsScreen(
            item: _item,
            locationService: _FakeLocationService.success(),
          ),
        ),
      );

      final photo = tester.widget<Image>(
        find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage),
      );
      expect(photo.fit, BoxFit.contain);
    },
  );

  testWidgets(
    'real-device UI pass: the photo header and the scrollable words area '
    'share the available height evenly (画面の約半分) rather than the '
    'photo using a small fixed pixel height',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          KotonohaWordsScreen(
            item: _item,
            locationService: _FakeLocationService.success(),
          ),
        ),
      );

      // find.ancestor walks upward from nearest to furthest — there are
      // two Expanded ancestors above each target (the inner photo/words
      // split, and the outer one wrapping the whole LeafDecoratedSection
      // below AdBanner), so take the nearest one specifically.
      final photoExpanded = tester
          .widgetList<Expanded>(
            find.ancestor(
              of: find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage),
              matching: find.byType(Expanded),
            ),
          )
          .first;
      final wordsExpanded = tester
          .widgetList<Expanded>(
            find.ancestor(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Expanded),
            ),
          )
          .first;

      expect(photoExpanded.flex, wordsExpanded.flex);
    },
  );
}
