import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_test/flutter_test.dart';

import 'package:omniversify_social_app/widgets/video_player.dart';

/// Fullscreen used to lock every clip to landscape, so a vertical video meant
/// rotating the phone to watch a strip of picture between two black columns.
/// The lock now follows the clip itself.
void main() {
  group('fullscreen orientation follows the clip', () {
    test('a vertical clip keeps the phone upright', () {
      expect(
        orientationsForClip(1080, 1920),
        [DeviceOrientation.portraitUp],
      );
    });

    test('a horizontal clip takes the width of the screen', () {
      expect(
        orientationsForClip(1920, 1080),
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      );
    });

    test('a clip whose size is not known yet behaves as it always did', () {
      // Nothing read from the header: landscape, which is what media_kit did
      // for every clip before this existed.
      expect(
        orientationsForClip(0, 0),
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      );
    });

    test('a square clip is treated as upright', () {
      expect(orientationsForClip(900, 900), [DeviceOrientation.portraitUp]);
    });
  });
}
