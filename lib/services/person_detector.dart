import 'dart:math';
import 'package:flutter/material.dart';

abstract class PersonDetector {
  /// Return a list of rectangles (in preview coordinate space) representing
  /// detected people. Rects should be expressed in preview coordinates
  /// where (0,0)-(width,height) is the preview area.
  Future<List<Rect>> detect(Size previewSize);
}

class MockPersonDetector implements PersonDetector {
  final Random _rnd = Random();

  @override
  Future<List<Rect>> detect(Size previewSize) async {
    // Simulate a small delay like a model would have.
    await Future.delayed(const Duration(milliseconds: 120));

    // Randomly choose 0..3 people
    final int count = _rnd.nextInt(4);
    final List<Rect> results = [];
    for (int i = 0; i < count; i++) {
      final w = previewSize.width * (0.15 + _rnd.nextDouble() * 0.25);
      final h = previewSize.height * (0.2 + _rnd.nextDouble() * 0.3);
      final x = _rnd.nextDouble() * (previewSize.width - w);
      final y = _rnd.nextDouble() * (previewSize.height - h);
      results.add(Rect.fromLTWH(x, y, w, h));
    }
    return results;
  }
}

// Placeholder for future TFLite implementation
class TFLitePersonDetector implements PersonDetector {
  @override
  Future<List<Rect>> detect(Size previewSize) async {
    // Implement model inference using tflite_flutter or ML Kit.
    throw UnimplementedError('TFLite detector not implemented yet');
  }
}
