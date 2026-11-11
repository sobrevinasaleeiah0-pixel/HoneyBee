import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'camera_mjpeg_preview_status.dart';

Widget buildCameraMjpegPreview({
  required String url,
  required int retryKey,
  required ValueChanged<CameraStreamStatus> onStatusChanged,
}) => _CameraMjpegPreviewWeb(
  url: url,
  retryKey: retryKey,
  onStatusChanged: onStatusChanged,
);

class _CameraMjpegPreviewWeb extends StatefulWidget {
  const _CameraMjpegPreviewWeb({
    required this.url,
    required this.retryKey,
    required this.onStatusChanged,
  });

  final String url;
  final int retryKey;
  final ValueChanged<CameraStreamStatus> onStatusChanged;

  @override
  State<_CameraMjpegPreviewWeb> createState() => _CameraMjpegPreviewWebState();
}

class _CameraMjpegPreviewWebState extends State<_CameraMjpegPreviewWeb> {
  static int _nextViewId = 0;
  static const _connectionTimeout = Duration(seconds: 12);
  static const _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];

  late final String _viewType;
  late final html.ImageElement _image;
  StreamSubscription<html.Event>? _loadSubscription;
  StreamSubscription<html.Event>? _errorSubscription;
  Timer? _connectionTimer;
  Timer? _retryTimer;
  CameraStreamStatus _status = CameraStreamStatus.connecting;
  String? _error;
  int _retryAttempt = 0;
  int _sourceAttempt = 0;

  @override
  void initState() {
    super.initState();
    _viewType = 'honeybee-mjpeg-${_nextViewId++}';
    _image = html.ImageElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = 'black';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _image,
    );
    _loadSubscription = _image.onLoad.listen((_) {
      _connectionTimer?.cancel();
      _retryAttempt = 0;
      _setStatus(CameraStreamStatus.connected);
    });
    _errorSubscription = _image.onError.listen((_) {
      _scheduleReconnect('The browser could not load the ESP32 MJPEG stream.');
    });
    _startStream();
  }

  @override
  void didUpdateWidget(covariant _CameraMjpegPreviewWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.retryKey != widget.retryKey) {
      _retryAttempt = 0;
      _startStream();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _connectionTimer?.cancel();
    _loadSubscription?.cancel();
    _errorSubscription?.cancel();
    _image.src = '';
    super.dispose();
  }

  String get _source {
    final uri = Uri.parse(widget.url);
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'reconnect': '${widget.retryKey}-$_sourceAttempt',
          },
        )
        .toString();
  }

  void _startStream() {
    _retryTimer?.cancel();
    _connectionTimer?.cancel();
    _sourceAttempt++;
    _setStatus(CameraStreamStatus.connecting);
    _image.src = '';
    _image.src = _source;
    _connectionTimer = Timer(_connectionTimeout, () {
      if (_status == CameraStreamStatus.connecting) {
        _scheduleReconnect('Timed out waiting for the first camera frame.');
      }
    });
  }

  void _scheduleReconnect(String error) {
    if (!mounted) return;
    _connectionTimer?.cancel();
    _setStatus(CameraStreamStatus.disconnected, error: error);
    final delay =
        _retryDelays[_retryAttempt < _retryDelays.length
            ? _retryAttempt
            : _retryDelays.length - 1];
    _retryAttempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, _startStream);
  }

  void _retryNow() {
    _retryAttempt = 0;
    _startStream();
  }

  void _setStatus(CameraStreamStatus status, {String? error}) {
    if (!mounted) return;
    if (_status == status && _error == error) return;
    setState(() {
      _status = status;
      _error = error;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onStatusChanged(status);
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      HtmlElementView(viewType: _viewType),
      if (_status != CameraStreamStatus.connected)
        ColoredBox(
          color: Colors.black87,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_status == CameraStreamStatus.connecting)
                    const CircularProgressIndicator(color: Colors.amber)
                  else
                    const Icon(
                      Icons.videocam_off_outlined,
                      color: Colors.white70,
                    ),
                  const SizedBox(height: 10),
                  Text(
                    _status == CameraStreamStatus.connecting
                        ? 'Connecting to ESP32 camera…'
                        : 'Camera disconnected${_error == null ? '.' : ':\n$_error'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  if (_status == CameraStreamStatus.disconnected)
                    TextButton.icon(
                      onPressed: _retryNow,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reconnect'),
                    ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
