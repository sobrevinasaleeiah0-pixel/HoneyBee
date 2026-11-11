import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'camera_mjpeg_preview_status.dart';

Widget buildCameraMjpegPreview({
  required String url,
  required int retryKey,
  required ValueChanged<CameraStreamStatus> onStatusChanged,
}) => _CameraMjpegPreviewIo(
  url: url,
  retryKey: retryKey,
  onStatusChanged: onStatusChanged,
);

class _CameraMjpegPreviewIo extends StatefulWidget {
  const _CameraMjpegPreviewIo({
    required this.url,
    required this.retryKey,
    required this.onStatusChanged,
  });

  final String url;
  final int retryKey;
  final ValueChanged<CameraStreamStatus> onStatusChanged;

  @override
  State<_CameraMjpegPreviewIo> createState() => _CameraMjpegPreviewIoState();
}

class _CameraMjpegPreviewIoState extends State<_CameraMjpegPreviewIo> {
  static const _connectTimeout = Duration(seconds: 8);
  static const _frameTimeout = Duration(seconds: 12);
  static const _maxFrameBytes = 5 * 1024 * 1024;
  static const _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];

  CameraStreamStatus _status = CameraStreamStatus.connecting;
  Uint8List? _frame;
  String? _error;
  HttpClient? _client;
  StreamSubscription<List<int>>? _subscription;
  Timer? _timeoutTimer;
  Timer? _retryTimer;
  List<int>? _currentFrame;
  bool _previousByteWasFf = false;
  int _connectionId = 0;
  int _retryAttempt = 0;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(covariant _CameraMjpegPreviewIo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.retryKey != widget.retryKey) {
      _retryAttempt = 0;
      _connect();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _timeoutTimer?.cancel();
    _subscription?.cancel();
    _client?.close(force: true);
    super.dispose();
  }

  void _setStatus(CameraStreamStatus status, {String? error}) {
    if (!mounted) return;
    if (_status != status || _error != error) {
      setState(() {
        _status = status;
        _error = error;
        if (status != CameraStreamStatus.connected) _frame = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onStatusChanged(status);
      });
    }
  }

  void _connect() {
    _retryTimer?.cancel();
    _timeoutTimer?.cancel();
    _subscription?.cancel();
    _client?.close(force: true);

    final connectionId = ++_connectionId;
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    _client = client;
    _currentFrame = null;
    _previousByteWasFf = false;
    _setStatus(CameraStreamStatus.connecting);
    _timeoutTimer = Timer(_connectTimeout, () {
      _fail(connectionId, 'Timed out waiting for the camera stream.');
    });
    unawaited(_openStream(connectionId, client));
  }

  Future<void> _openStream(int connectionId, HttpClient client) async {
    try {
      final uri = Uri.parse(widget.url);
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        throw const FormatException(
          'Camera stream URL must use HTTP or HTTPS.',
        );
      }

      final request = await client.getUrl(uri).timeout(_connectTimeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'multipart/x-mixed-replace',
      );
      final response = await request.close().timeout(_connectTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Camera returned HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      if (response.headers.contentType?.mimeType !=
          'multipart/x-mixed-replace') {
        throw const FormatException('Camera response is not an MJPEG stream.');
      }

      if (connectionId != _connectionId || !mounted) return;
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(_frameTimeout, () {
        _fail(connectionId, 'No camera frames received.');
      });
      _subscription = response.listen(
        (bytes) => _consumeBytes(connectionId, bytes),
        onError: (Object error, StackTrace stackTrace) {
          _fail(connectionId, error.toString());
        },
        onDone: () => _fail(connectionId, 'Camera stream disconnected.'),
        cancelOnError: true,
      );
    } catch (error) {
      _fail(connectionId, error.toString());
    }
  }

  void _consumeBytes(int connectionId, List<int> bytes) {
    if (connectionId != _connectionId || !mounted) return;
    for (final byte in bytes) {
      final frame = _currentFrame;
      if (frame == null) {
        if (_previousByteWasFf && byte == 0xd8) {
          _currentFrame = [0xff, 0xd8];
          _previousByteWasFf = false;
        } else {
          _previousByteWasFf = byte == 0xff;
        }
        continue;
      }

      frame.add(byte);
      if (frame.length > _maxFrameBytes) {
        _fail(connectionId, 'Camera frame exceeded the supported size.');
        return;
      }

      if (_previousByteWasFf && byte == 0xd9) {
        _currentFrame = null;
        _previousByteWasFf = false;
        _timeoutTimer?.cancel();
        _timeoutTimer = Timer(_frameTimeout, () {
          _fail(connectionId, 'Camera stream stopped sending frames.');
        });
        setState(() {
          _frame = Uint8List.fromList(frame);
          _status = CameraStreamStatus.connected;
          _error = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onStatusChanged(CameraStreamStatus.connected);
          }
        });
        _retryAttempt = 0;
      } else {
        _previousByteWasFf = byte == 0xff;
      }
    }
  }

  void _fail(int connectionId, String message) {
    if (connectionId != _connectionId || !mounted) return;
    _connectionId++;
    _timeoutTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _client?.close(force: true);
    _client = null;
    _currentFrame = null;
    _setStatus(CameraStreamStatus.disconnected, error: message);

    final delay =
        _retryDelays[_retryAttempt < _retryDelays.length
            ? _retryAttempt
            : _retryDelays.length - 1];
    _retryAttempt++;
    _retryTimer = Timer(delay, _connect);
  }

  void _retryNow() {
    _retryAttempt = 0;
    _connect();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame != null) {
      return Image.memory(
        frame,
        key: ValueKey(frame),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _statusOverlay('Unable to decode camera frame.', retry: false),
      );
    }

    if (_status == CameraStreamStatus.connecting) {
      return _statusOverlay('Connecting to ESP32 camera…', loading: true);
    }
    return _statusOverlay(
      'Camera disconnected${_error == null ? '.' : ':\n$_error'}',
      retry: true,
    );
  }

  Widget _statusOverlay(
    String message, {
    bool loading = false,
    bool retry = false,
  }) => ColoredBox(
    color: Colors.black87,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator(color: Colors.amber)
            else
              const Icon(Icons.videocam_off_outlined, color: Colors.white70),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (retry)
              TextButton.icon(
                onPressed: _retryNow,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reconnect'),
              ),
          ],
        ),
      ),
    ),
  );
}
