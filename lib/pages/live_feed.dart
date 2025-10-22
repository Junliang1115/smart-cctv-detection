import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import '../services/person_detector.dart';

class LiveFeedPage extends StatefulWidget {
  final CameraDescription camera;
  const LiveFeedPage({super.key, required this.camera});

  @override
  State<LiveFeedPage> createState() => _LiveFeedPageState();
}

class _LiveFeedPageState extends State<LiveFeedPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  // Ambient light detection
  double _smoothedLuma = 0.0;
  DateTime _lastLumaUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _streaming = false;

  // Throttle interval for processing frames
  final Duration _lumaThrottle = const Duration(milliseconds: 200);
  // Person detection
  final PersonDetector _detector = MockPersonDetector();
  List<Rect> _detectedBoxes = [];
  Timer? _detectionTimer;
  final Duration _detectionInterval = const Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize();
    _initializeControllerFuture.then((_) {
      // start detection loop after initialization
      _startDetectionLoop();
    });
  }

  @override
  void dispose() {
    if (_streaming) {
      try {
        _controller.stopImageStream();
      } catch (_) {}
    }
    _detectionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Feed')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // Start image stream (if supported) to measure ambient light.
            if (!_streaming) {
              try {
                _controller.startImageStream(_processCameraImage);
                _streaming = true;
              } catch (_) {
                // Some platforms may not support imageStream; ignore.
              }
            }

            // Center the camera preview in the screen and overlay luma indicator
            return Stack(
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: CameraPreview(_controller),
                  ),
                ),
                // detection overlay
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _DetectionPainter(_detectedBoxes),
                    ),
                  ),
                ),
                Positioned(left: 12, bottom: 12, child: _buildLumaIndicator()),
                Positioned(right: 12, top: 12, child: _buildPersonCountBadge()),
              ],
            );
          } else if (snapshot.hasError) {
            return Center(child: Text('Camera error: ${snapshot.error}'));
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }

  void _startDetectionLoop() {
    _detectionTimer = Timer.periodic(_detectionInterval, (_) async {
      try {
        Size previewSize = _controller.value.previewSize ?? Size(640, 480);
        // previewSize may be physical pixels; map to logical if needed
        final boxes = await _detector.detect(previewSize);
        if (mounted) setState(() => _detectedBoxes = boxes);
      } catch (e) {
        // ignore
      }
    });
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
            '${_detectedBoxes.length} people',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // Process incoming camera images to compute average luminance.
  void _processCameraImage(CameraImage image) {
    // Throttle updates to reduce CPU usage.
    final now = DateTime.now();
    if (now.difference(_lastLumaUpdate) < _lumaThrottle) return;
    _lastLumaUpdate = now;

    double luma = 0.0;
    int pixelCount = 0;

    try {
      // Y plane is available on YUV420 formats and contains luma
      final Plane yPlane = image.planes.first;
      final Uint8List bytes = yPlane.bytes;
      // Sample the plane instead of every pixel for speed.
      const int step = 8; // adjust for speed/accuracy tradeoff
      for (int i = 0; i < bytes.length; i += step) {
        luma += bytes[i];
        pixelCount++;
      }
      if (pixelCount > 0) {
        final double avg = luma / pixelCount; // 0..255
        // Normalize to 0..1
        final double normalized = (avg / 255.0).clamp(0.0, 1.0);
        // Exponential smoothing
        const double alpha = 0.2;
        _smoothedLuma = (_smoothedLuma * (1 - alpha)) + (normalized * alpha);
        // update UI
        if (mounted) setState(() {});
      }
    } catch (e) {
      // ignore image processing errors
    }
  }

  Widget _buildLumaIndicator() {
    // Map smoothed value to percent and color
    final percent = (_smoothedLuma * 100).round();
    Color badgeColor;
    if (_smoothedLuma < 0.25) {
      badgeColor = Colors.black;
    } else if (_smoothedLuma < 0.5) {
      badgeColor = Colors.orange;
    } else {
      badgeColor = Colors.yellow.shade700;
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
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$percent% lighting',
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
      canvas.drawRect(r, paint);
      final tp = TextPainter(
        text: TextSpan(
          text: 'Person ${i + 1}',
          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(
          r.left,
          (r.top - tp.height - 4).clamp(0.0, size.height - tp.height),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) =>
      oldDelegate.boxes != boxes;
}
