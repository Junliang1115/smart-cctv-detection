import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Detection painter
class DetectionPainter extends CustomPainter {
  final List<Rect> boxes;
  DetectionPainter(this.boxes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.redAccent;
    for (int i = 0; i < boxes.length; i++) {
      final r = boxes[i];
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
  bool shouldRepaint(covariant DetectionPainter oldDelegate) =>
      oldDelegate.boxes != boxes;
}

class UploadVideoPage extends StatefulWidget {
  const UploadVideoPage({super.key});

  @override
  State<UploadVideoPage> createState() => _UploadVideoPageState();
}

class _UploadVideoPageState extends State<UploadVideoPage> {
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  List<_DetectedFrame> _frames = [];
  int _current = 0;
  final PageController _pageController = PageController(initialPage: 0);
  bool _hasAttemptedUpload = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Use native file picker instead of manual path entry on desktop

  Future<String?> _askForLocalPath() async {
    String? path;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Enter local video path'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: r'C:\path\to\video.mp4',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                path = controller.text.trim();
                Navigator.of(ctx).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    return path;
  }

  Future<void> _pickAndUpload() async {
    final path = await _askForLocalPath();
    if (path == null || path.isEmpty) return;
    await _uploadVideoFile(path);
  }

  Future<void> _uploadVideoFile(String path) async {
    setState(() {
      _isUploading = true;
      _hasAttemptedUpload = true;
      _uploadProgress = 0.0;
      _frames = [];
    });
    try {
      final uri = Uri.parse('http://localhost:8000/detect_video');
      final req = http.MultipartRequest('POST', uri);
      req.fields['sample_rate'] = '15';
      req.fields['conf'] = '0.25';
      final file = await http.MultipartFile.fromPath('video', path);
      req.files.add(file);
      final streamed = await req.send();
      final resp = await http.Response.fromStream(
        streamed,
      ).timeout(const Duration(minutes: 5));
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        final List frames = body['frames'] as List? ?? [];
        final parsed = <_DetectedFrame>[];
        for (final f in frames) {
          Uint8List? imageBytes;
          if (f.containsKey('image_b64')) {
            try {
              imageBytes = base64.decode(f['image_b64'] as String);
            } catch (_) {}
          }
          final boxes = <Rect>[];
          final bl = f['boxes'] as List? ?? [];
          for (final b in bl) {
            final double x = (b['x'] as num).toDouble();
            final double y = (b['y'] as num).toDouble();
            final double bw = (b['width'] as num).toDouble();
            final double bh = (b['height'] as num).toDouble();
            boxes.add(Rect.fromLTWH(x, y, bw, bh));
          }
          parsed.add(
            _DetectedFrame(
              imageBytes,
              boxes,
              (f['people_count'] as int?) ?? boxes.length,
            ),
          );
        }
        setState(() {
          _frames = parsed;
          _current = 0;
          // make sure page controller shows first page
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _pageController.jumpToPage(0);
          });
        });
      }
    } catch (e) {
      // ignore
    } finally {
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Video for Detection')),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _pickAndUpload,
                icon: const Icon(Icons.upload_file),
                label: const Text('Choose & Upload'),
              ),
              if (_isUploading)
                LinearProgressIndicator(
                  value: _uploadProgress == 0.0 ? null : _uploadProgress,
                ),
              const SizedBox(height: 12),
              Expanded(
                child:
                    _frames.isEmpty
                        ? (_hasAttemptedUpload
                            ? const Center(child: Text('No video found'))
                            : const Center(child: Text('No results yet')))
                        : Column(
                          children: [
                            Expanded(
                              child: PageView.builder(
                                controller: _pageController,
                                itemCount: _frames.length,
                                onPageChanged:
                                    (i) => setState(() => _current = i),
                                itemBuilder: (ctx, i) {
                                  final f = _frames[i];
                                  return Stack(
                                    children: [
                                      if (f.imageBytes != null)
                                        Positioned.fill(
                                          child: Image.memory(
                                            f.imageBytes!,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: CustomPaint(
                                            painter: DetectionPainter(f.boxes),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: 12,
                                        top: 12,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          color: Colors.white70,
                                          child: Text(
                                            'Frame ${i + 1} — ${f.peopleCount} people',
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            SizedBox(
                              height: 48,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    onPressed:
                                        (_current <= 0)
                                            ? null
                                            : () {
                                              final prev = _current - 1;
                                              _pageController.animateToPage(
                                                prev,
                                                duration: const Duration(
                                                  milliseconds: 250,
                                                ),
                                                curve: Curves.easeInOut,
                                              );
                                            },
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Frame ${_current + 1} / ${_frames.length}',
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed:
                                        (_current >= _frames.length - 1)
                                            ? null
                                            : () {
                                              final next = _current + 1;
                                              _pageController.animateToPage(
                                                next,
                                                duration: const Duration(
                                                  milliseconds: 250,
                                                ),
                                                curve: Curves.easeInOut,
                                              );
                                            },
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
              ),
            ],
          ),

          // Full-screen loading overlay while upload/analysis is in progress
          if (_isUploading)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Analyzing video...',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetectedFrame {
  final Uint8List? imageBytes;
  final List<Rect> boxes;
  final int peopleCount;
  _DetectedFrame(this.imageBytes, this.boxes, this.peopleCount);
}
