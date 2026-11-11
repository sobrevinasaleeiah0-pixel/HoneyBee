import 'package:flutter_test/flutter_test.dart';
import 'package:honeybee_center/widgets/camera_mjpeg_preview.dart';

void main() {
  group('cameraMjpegStreamUrl', () {
    test('uses the verified CameraWebServer stream port and path', () {
      expect(
        cameraMjpegStreamUrl('192.168.1.50'),
        'http://192.168.1.50:81/stream',
      );
    });

    test('preserves a configured explicit port', () {
      expect(
        cameraMjpegStreamUrl('http://camera.local:8081/old-path'),
        'http://camera.local:8081/stream',
      );
    });

    test('rejects unsupported or invalid addresses', () {
      expect(cameraMjpegStreamUrl('ftp://camera.local'), isNull);
      expect(cameraMjpegStreamUrl('not a camera address'), isNull);
      expect(cameraMjpegStreamUrl(''), isNull);
    });
  });
}
