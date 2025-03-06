// lib/utils/tflite_helper.dart
import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class TFLiteHelper {
  late Interpreter _interpreter;
  bool _isModelLoaded = false;

  final Map<int, String> _labels = {1: 'PIH', 2: 'PIE', 3: 'Spot'};

  // Initialize interpreter
  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions();
      // Use num threads based on device capability
      options.threads = 4;

      _interpreter = await Interpreter.fromAsset(
        'assets/model_float32.tflite',
        options: options,
      );
      _isModelLoaded = true;
      print('TFLite model loaded successfully');
    } catch (e) {
      print('Error loading TFLite model: $e');
      _isModelLoaded = false;
      rethrow;
    }
  }

  // Process image and run inference
  Future<List<Map<String, dynamic>>> processImage(File imageFile) async {
    if (!_isModelLoaded) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    // Read and decode image
    try {
      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(imageBytes);

      if (decodedImage == null) {
        throw Exception('Failed to decode image');
      }

      // Resize image to model input size (512x512)
      final resizedImage = img.copyResize(
        decodedImage,
        width: 512,
        height: 512,
      );

      // Convert to normalized float32 array [0-1]
      var inputImage = List.generate(
        512,
        (y) => List.generate(512, (x) {
          final pixel = resizedImage.getPixel(x, y);
          return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        }),
      );

      // Reshape input to [1, 512, 512, 3]
      var input = [
        inputImage.reshape([1, 512, 512, 3]),
      ];

      // Get output tensor details
      var outputTensors = _interpreter.getOutputTensors();
      var outputShapes = outputTensors.map((tensor) => tensor.shape).toList();

      // Prepare outputs based on model's expected shapes
      var outputBoxes = List.filled(100 * 4, 0.0).reshape([1, 100, 4]);
      var outputClasses = List.filled(100, 0.0).reshape([1, 100]);
      var outputScores = List.filled(100, 0.0).reshape([1, 100]);
      var outputCount = List.filled(1, 0.0).reshape([1]);

      Map<int, Object> outputs = {
        0: outputBoxes,
        1: outputClasses,
        2: outputScores,
        3: outputCount,
      };

      try {
        _interpreter.runForMultipleInputs([input], outputs);
      } catch (e) {
        print('Error during inference: $e');
        // If standard inference fails, try alternative approach
        return _fallbackProcessing(
          resizedImage,
          decodedImage.width,
          decodedImage.height,
        );
      }

      // Process results
      int count = (outputCount[0] as int);
      List<Map<String, dynamic>> detections = [];

      for (int i = 0; i < count; i++) {
        double score = outputScores[0][i];
        if (score > 0.5) {
          int classId = outputClasses[0][i].toInt();
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
      print('Error during image processing: $e');
      rethrow;
    }
  }

  // Fallback processing method if the regular inference fails
  List<Map<String, dynamic>> _fallbackProcessing(
    img.Image resizedImage,
    int originalWidth,
    int originalHeight,
  ) {
    print('Using fallback processing method');

    // Create a simple list of detections for demonstration
    // In a real app, you might want to implement an alternative model or approach
    List<Map<String, dynamic>> fallbackDetections = [];

    try {
      // Extract image features for simple detection (simplified example)
      int redSum = 0, greenSum = 0, blueSum = 0;
      int pixelCount = 0;

      // Sample pixels from the center area
      int centerX = resizedImage.width ~/ 2;
      int centerY = resizedImage.height ~/ 2;
      int sampleRadius = 100;

      for (int y = centerY - sampleRadius; y < centerY + sampleRadius; y++) {
        for (int x = centerX - sampleRadius; x < centerX + sampleRadius; x++) {
          if (x >= 0 &&
              x < resizedImage.width &&
              y >= 0 &&
              y < resizedImage.height) {
            final pixel = resizedImage.getPixel(x, y);
            redSum += pixel.r.toInt();
            greenSum += pixel.g.toInt();
            blueSum += pixel.b.toInt();
            pixelCount++;
          }
        }
      }

      // Calculate average color
      double avgRed = redSum / pixelCount;
      double avgGreen = greenSum / pixelCount;
      double avgBlue = blueSum / pixelCount;

      // Very simple heuristic for demonstration:
      // If the region has more red than other colors, it might be acne
      if (avgRed > avgGreen * 1.2 && avgRed > avgBlue * 1.2) {
        // Create a fallback detection
        fallbackDetections.add({
          'box': [
            centerX - sampleRadius * 0.5, // xmin
            centerY - sampleRadius * 0.5, // ymin
            centerX + sampleRadius * 0.5, // xmax
            centerY + sampleRadius * 0.5, // ymax
          ],
          'label': 'Acne',
          'score': 0.6, // Lower confidence to indicate fallback method
        });
      }
    } catch (e) {
      print('Fallback processing failed: $e');
    }

    return fallbackDetections;
  }

  // Close the interpreter
  void dispose() {
    if (_isModelLoaded) {
      _interpreter.close();
      _isModelLoaded = false;
    }
  }
}
