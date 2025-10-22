import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Person detection state (boxes are in widget coordinates)
List<Rect> _windowsDetectedBoxes = [];
Timer? _windowsDetectionTimer;
final Duration _windowsDetectionInterval = const Duration(milliseconds: 700);

// Backend config - change if your FastAPI server lives elsewhere
const String _detectionBackendUrl = 'http://localhost:8000/detect';

class LiveFeedWindows extends StatefulWidget {
  const LiveFeedWindows({super.key});

  @override
  State<LiveFeedWindows> createState() => _LiveFeedWindowsState();
}

class _LiveFeedWindowsState extends State<LiveFeedWindows> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  // Capture & brightness detection
  final GlobalKey _videoKey = GlobalKey();
  Timer? _captureTimer;
  double _smoothedLuma = 0.0;
  String _brightnessCategory = 'Unknown';
  final Duration _captureInterval = const Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _openCamera();
    _startCaptureTimer();
    _startWindowsDetection();
  }

  Future<void> _initRenderer() async {
    await _localRenderer.initialize();
  }

  Future<void> _openCamera() async {
    try {
      final Map<String, dynamic> mediaConstraints = {
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': 1280,
          'height': 720,
          'frameRate': 30,
        },
      };
      final stream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );
      _localStream = stream;
      _localRenderer.srcObject = _localStream;
      setState(() {});
    } catch (e) {
      // ignore: avoid_print
      print('Error opening camera: $e');
    }
  }

  void _startCaptureTimer() {
    _captureTimer = Timer.periodic(_captureInterval, (_) async {
      await _captureAndAnalyze();
    });
  }

  void _startWindowsDetection() {
    _windowsDetectionTimer = Timer.periodic(_windowsDetectionInterval, (
      _,
    ) async {
      try {
        final boundary =
            _videoKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary == null) return;
        // capture a smaller image for speed
        final ui.Image image = await boundary.toImage(pixelRatio: 0.5);
        final ByteData? byteData = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (byteData == null) return;
        final bytes = byteData.buffer.asUint8List();
        // Upload to backend and parse response
        final resp = await _uploadImageForDetection(bytes);
        if (resp != null) {
          // Map normalized boxes to widget coordinates (we store normalized boxes)
          // Store normalized boxes (relative 0..1). We'll scale in painter to widget size.
          final List<Rect> mapped = [];
          for (final b in resp['boxes'] as List) {
            final double x = (b['x'] as num).toDouble();
            final double y = (b['y'] as num).toDouble();
            final double bw = (b['width'] as num).toDouble();
            final double bh = (b['height'] as num).toDouble();
            mapped.add(Rect.fromLTWH(x, y, bw, bh));
          }
          _windowsDetectedBoxes = mapped;
          // prefer backend brightness if provided
          if (resp.containsKey('brightness_category')) {
            _brightnessCategory = resp['brightness_category'] as String;
          }
          if (mounted) setState(() {});
        }
      } catch (e) {
        // ignore detection errors
      }
    });
  }

  Future<void> _captureAndAnalyze() async {
    try {
      // Try to capture the widget as image. This may fail on some platforms
      // when the video is rendered by a platform texture. We guard and ignore
      // failures.
      final boundary =
          _videoKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 0.5);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return;
      final Uint8List bytes = byteData.buffer.asUint8List();
      // bytes are RGBA
      int sampleCount = 0;
      double luma = 0.0;
      const int step = 8; // sample every 8th byte group for speed
      for (int i = 0; i + 3 < bytes.length; i += 4 * step) {
        final int r = bytes[i];
        final int g = bytes[i + 1];
        final int b = bytes[i + 2];
        // luminance approximation
        luma += 0.2126 * r + 0.7152 * g + 0.0722 * b;
        sampleCount++;
      }
      if (sampleCount == 0) return;
      final double avg = (luma / sampleCount) / 255.0; // normalized 0..1
      // exponential smoothing
      const double alpha = 0.25;
      _smoothedLuma = (_smoothedLuma * (1 - alpha)) + (avg * alpha);
      // classify into three categories
      String cat;
      if (_smoothedLuma < 0.12) {
        cat = 'Very dark';
      } else if (_smoothedLuma < 0.40) {
        cat = 'Shallow';
      } else {
        cat = 'Normal';
      }
      if (mounted) {
        setState(() {
          _brightnessCategory = cat;
        });
      }
    } catch (e) {
      // ignore capture errors; keep previous category or Unknown
    }
  }

  Future<Map<String, dynamic>?> _uploadImageForDetection(
    Uint8List pngBytes,
  ) async {
    try {
      final uri = Uri.parse(_detectionBackendUrl);
      final req = http.MultipartRequest('POST', uri);
      req.files.add(
        http.MultipartFile.fromBytes(
          'image',
          pngBytes,
          filename: 'frame.png',
          contentType: null,
        ),
      );
      final streamed = await req.send().timeout(const Duration(seconds: 6));
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        return json.decode(resp.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      // ignore network or timeout errors
      return null;
    }
  }

  @override
  void dispose() {
    _localStream?.getTracks().forEach((t) => t.stop());
    _localRenderer.dispose();
    _captureTimer?.cancel();
    _windowsDetectionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Feed (Windows)')),
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            RepaintBoundary(
              key: _videoKey,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: Colors.black,
                  child: RTCVideoView(
                    _localRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),
            // Detection overlay
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DetectionPainter(_windowsDetectedBoxes),
                ),
              ),
            ),
            Positioned(right: 12, top: 12, child: _buildPersonCountBadge()),
            Positioned(left: 12, bottom: 12, child: _buildLumaIndicator()),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonCountBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white70,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person, size: 18),
          const SizedBox(width: 8),
          Text(
            '${_windowsDetectedBoxes.length} people',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildLumaIndicator() {
    Color color;
    switch (_brightnessCategory) {
      case 'Very dark':
        color = Colors.black;
        break;
      case 'Shallow':
        color = Colors.orange;
        break;
      case 'Normal':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white70,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            _brightnessCategory,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  final List<Rect> boxes;
  _DetectionPainter(this.boxes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.redAccent;
    for (int i = 0; i < boxes.length; i++) {
      final r = boxes[i];
      // r is normalized (0..1) relative to the captured image
      final left = r.left * size.width;
      final top = r.top * size.height;
      final width = r.width * size.width;
      final height = r.height * size.height;
      final rect = Rect.fromLTWH(left, top, width, height);
      canvas.drawRect(rect, paint);
      final tp = TextPainter(
        text: TextSpan(
          text: 'Person ${i + 1}',
          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      final labelY = (top - tp.height - 4).clamp(0.0, size.height - tp.height);
      tp.paint(canvas, Offset(left, labelY));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) =>
      oldDelegate.boxes != boxes;
}
