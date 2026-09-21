import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kotonoha/screens/camera_capture_screen.dart';

/// Real device apps genuinely have a camera, so [CameraCaptureScreen]'s
/// "ready, streaming video" state can't be meaningfully exercised in
/// `flutter test` at all (no platform view/texture is ever actually
/// rendered) — but its "no camera available" error state *is* reachable
/// with nothing more than [availableCameras] stubbed out, and that state
/// goes through this screen's exact same Scaffold/Stack/back-button
/// structure as the streaming-video state (see camera_capture_screen.dart
/// build()/_buildCameraLayer()) — only the content inside that structure
/// differs. This is enough to verify, with a real (if minimal) code path
/// rather than a widget built by hand to match the assertions: no AppBar
/// and no "言の葉を置く" text anywhere in camera mode (real-device fix
/// item 3), and that a working back action is overlaid on it regardless
/// (item 4).
class _EmptyCameraPlatform extends CameraPlatform {
  @override
  Future<List<CameraDescription>> availableCameras() async => const [];
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  late CameraPlatform originalPlatform;

  setUp(() {
    originalPlatform = CameraPlatform.instance;
    CameraPlatform.instance = _EmptyCameraPlatform();
  });

  tearDown(() {
    CameraPlatform.instance = originalPlatform;
  });

  testWidgets(
    '実機修正: camera mode has no AppBar and never shows "言の葉を置く" '
    '(that title now only appears on the post-capture review screen, '
    'unchanged)',
    (tester) async {
      await tester.pumpWidget(_wrap(const CameraCaptureScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('言の葉を置く'), findsNothing);
    },
  );

  testWidgets(
    '実機修正: a back button is overlaid on camera mode and pops the '
    'screen when tapped',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(CameraCaptureScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(CameraCaptureScreen), findsNothing);
    },
  );

  testWidgets(
    'the existing "no camera found" error message still renders (this '
    'layout pass never touched that logic)',
    (tester) async {
      await tester.pumpWidget(_wrap(const CameraCaptureScreen()));
      await tester.pumpAndSettle();

      expect(find.text('カメラが見つかりませんでした。'), findsOneWidget);
    },
  );

  testWidgets(
    '実機修正: the whole camera-mode Scaffold body is a single '
    'StackFit.expand Stack (back button + content layered directly on '
    'top of each other, filling the screen) rather than a Column that '
    'reserves separate rows for each',
    (tester) async {
      await tester.pumpWidget(_wrap(const CameraCaptureScreen()));
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.body, isA<Stack>());
      expect((scaffold.body! as Stack).fit, StackFit.expand);
    },
  );
}
