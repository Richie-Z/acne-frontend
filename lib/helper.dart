import 'dart:io';
import 'package:flutter/material.dart' show debugPrint;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class TFLiteHelper {
  late Interpreter _interpreter;
  bool _isModelLoaded = false;

  final Map<int, String> _labels = {1: 'PIH', 2: 'PIE', 3: 'Spot'};

  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        'assets/model_float16.tflite',
        options: options,
      );
      _isModelLoaded = true;
      debugPrint('TFLite model loaded successfully');
    } catch (e) {
      debugPrint('Error loading TFLite model: $e');
      _isModelLoaded = false;
    }
  }

  Future<List<Map<String, dynamic>>> processImage(File imageFile) async {
    if (!_isModelLoaded) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    try {
      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        throw Exception('Failed to decode image');
      }

      final resizedImage = img.copyResize(
        decodedImage,
        width: 512,
        height: 512,
      );

      var inputBuffer = List<double>.filled(512 * 512 * 3, 0.0);
      int index = 0;
      for (int y = 0; y < 512; y++) {
        for (int x = 0; x < 512; x++) {
          final pixel = resizedImage.getPixel(x, y);
          inputBuffer[index++] = pixel.r / 255.0;
          inputBuffer[index++] = pixel.g / 255.0;
          inputBuffer[index++] = pixel.b / 255.0;
        }
      }

      var input = inputBuffer.reshape([1, 3, 512, 512]);

      int maxBoxes = 100;
      var outputBoxes = List.filled(
        maxBoxes * 4,
        0.0,
      ).reshape([1, maxBoxes, 4]);
      var outputScores = List.filled(maxBoxes, 0.0).reshape([1, maxBoxes]);
      var outputLabels = List.filled(maxBoxes, 0.0).reshape([1, maxBoxes]);
      var outputCount = List.filled(1, 0.0).reshape([1]);

      debugPrint('Boxes shape: ${outputBoxes.shape}');
      debugPrint('Scores shape: ${outputScores.shape}');
      debugPrint('Labels shape: ${outputLabels.shape}');
      debugPrint('Count: ${outputCount[0]}');

      Map<int, Object> outputs = {
        0: outputBoxes,
        1: outputScores,
        2: outputLabels,
        3: outputCount,
      };

      _interpreter.runForMultipleInputs([input], outputs);

      int count = outputCount[0].toInt();
      List<Map<String, dynamic>> detections = [];

      // Process only valid detections
      for (int i = 0; i < count; i++) {
        double score = outputScores[0][i];
        if (score > 0.3) {
          int classId = outputLabels[0][i].toInt();
          String label = _labels[classId] ?? 'Unknown';
          List<double> box = [
            outputBoxes[0][i][0] * decodedImage.width,
            outputBoxes[0][i][1] * decodedImage.height,
            outputBoxes[0][i][2] * decodedImage.width,
            outputBoxes[0][i][3] * decodedImage.height,
          ];
          detections.add({'box': box, 'label': label, 'score': score});
        }
      }

      return detections;
    } catch (e) {
      debugPrint('Error during image processing: $e');
      rethrow;
    }
  }

  void dispose() {
    if (_isModelLoaded) {
      _interpreter.close();
      _isModelLoaded = false;
    }
  }
}
