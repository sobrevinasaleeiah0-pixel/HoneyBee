import 'package:flutter/material.dart';

import 'camera_mjpeg_preview_status.dart';
import 'camera_mjpeg_preview_io.dart'
    if (dart.library.html) 'camera_mjpeg_preview_web.dart'
    as platform;

export 'camera_mjpeg_preview_status.dart';

String? cameraMjpegStreamUrl(String address) {
  final input = address.trim();
  final normalized = input.contains('://') ? input : 'http://$input';
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      !RegExp(r'^[A-Za-z0-9.:-]+$').hasMatch(uri.host) ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
    return null;
  }

  return uri
      .replace(
        port: uri.hasPort ? uri.port : 81,
        path: '/stream',
        query: null,
        fragment: null,
      )
      .toString();
}

class CameraMjpegPreview extends StatelessWidget {
  const CameraMjpegPreview({
    super.key,
    required this.url,
    required this.retryKey,
    required this.onStatusChanged,
  });

  final String url;
  final int retryKey;
  final ValueChanged<CameraStreamStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) => platform.buildCameraMjpegPreview(
    url: url,
    retryKey: retryKey,
    onStatusChanged: onStatusChanged,
  );
}
