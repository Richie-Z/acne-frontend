// lib/main.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'dart:ui' as ui;
import 'helper.dart'; // Import the helper

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Get available cameras
  final cameras = await availableCameras();

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Acne Detection',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: CameraScreen(cameras: cameras),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isFrontCamera = false;
  bool _isProcessing = false;
  double _processingProgress = 0.0; // Track processing progress
  File? _capturedImage;
  List<Map<String, dynamic>>? _detections;
  late TFLiteHelper _tfliteHelper; // Use the helper class

  @override
  void initState() {
    super.initState();
    // Initialize camera with back camera first
    _initializeCamera(widget.cameras[0]);
    // Initialize TFLite helper
    _tfliteHelper = TFLiteHelper();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      await _tfliteHelper.loadModel();
    } catch (e) {
      print('Error loading model: $e');
    }
  }

  void _initializeCamera(CameraDescription camera) {
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    _initializeControllerFuture = _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _tfliteHelper.dispose(); // Dispose the helper
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    final CameraDescription newCamera =
        _isFrontCamera
            ? widget.cameras[0] // Back camera
            : widget.cameras[1]; // Front camera

    await _controller.dispose();
    _initializeCamera(newCamera);

    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }

  Future<void> _captureImage() async {
    try {
      await _initializeControllerFuture;
      final XFile image = await _controller.takePicture();

      setState(() {
        _capturedImage = File(image.path);
        _isProcessing = true;
        _processingProgress = 0.0; // Reset progress
      });

      // Process image immediately without simulated progress
      await _processImage();

      setState(() {
        _isProcessing = false;
      });
    } catch (e) {
      print('Error capturing image: $e');
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _processImage() async {
    if (_capturedImage == null) return;

    try {
      // Use the TFLite helper to process the image
      final detections = await _tfliteHelper.processImage(_capturedImage!);

      if (mounted) {
        setState(() {
          _detections = detections;
        });
      }
    } catch (e) {
      print('Error processing image: $e');
    }
  }

  void _resetCamera() {
    setState(() {
      _capturedImage = null;
      _detections = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acne Detection'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _capturedImage == null ? _buildCameraView() : _buildResultView(),
    );
  }

  Widget _buildCameraView() {
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return Column(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Camera preview
                    CameraPreview(_controller),

                    // Camera controls overlay
                    Positioned(
                      bottom: 30,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Toggle camera button
                          if (widget.cameras.length > 1)
                            IconButton(
                              icon: const Icon(Icons.flip_camera_ios),
                              color: Colors.white,
                              iconSize: 32,
                              onPressed: _toggleCamera,
                            ),

                          // Capture button
                          GestureDetector(
                            onTap: _captureImage,
                            child: Container(
                              height: 70,
                              width: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                              child: Container(
                                margin: const EdgeInsets.all(5),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),

                          // Placeholder for symmetry
                          const SizedBox(width: 32),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }

  Widget _buildResultView() {
    return Column(
      children: [
        Expanded(
          child:
              _isProcessing
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 100,
                              height: 100,
                              child: CircularProgressIndicator(
                                value: _processingProgress,
                                strokeWidth: 8,
                                backgroundColor: Colors.grey[300],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            Text(
                              '${(_processingProgress * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Processing image...',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Analyzing skin conditions',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                  : Stack(
                    fit: StackFit.expand,
                    children: [
                      // Display captured image
                      Image.file(_capturedImage!, fit: BoxFit.contain),

                      // Draw detection boxes
                      if (_detections != null)
                        CustomPaint(
                          painter: BoundingBoxPainter(
                            _detections!,
                            _capturedImage!,
                          ),
                          size: Size.infinite,
                        ),
                    ],
                  ),
        ),

        // Bottom controls
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text('New Capture'),
                onPressed: _resetCamera,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
              if (_detections != null && _detections!.isNotEmpty)
                Text(
                  'Found: ${_detections!.length} ${_detections!.length == 1 ? 'issue' : 'issues'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<Map<String, dynamic>> detections;
  final File image;

  BoundingBoxPainter(this.detections, this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final Map<String, Color> classColors = {
      'PIH': Colors.red,
      'PIE': Colors.orange,
      'Spot': Colors.purple,
    };

    for (var detection in detections) {
      final List<double> box = detection['box'];
      final String label = detection['label'];
      final double score = detection['score'];
      final Color boxColor = classColors[label] ?? Colors.red;

      // Calculate scale factors based on canvas size
      final double imageAspectRatio =
          box[2] - box[0] > 0 && box[3] - box[1] > 0
              ? (box[2] - box[0]) / (box[3] - box[1])
              : 1.0;
      final double canvasAspectRatio = size.width / size.height;

      double scaleX, scaleY;
      double offsetX = 0, offsetY = 0;

      if (canvasAspectRatio > imageAspectRatio) {
        // Canvas is wider than image
        scaleY =
            size.height / (box[3] - box[1] > 0 ? box[3] - box[1] + box[1] : 1);
        scaleX = scaleY;
        offsetX = (size.width - (box[2] - box[0]) * scaleX) / 2;
      } else {
        // Canvas is taller than image
        scaleX =
            size.width / (box[2] - box[0] > 0 ? box[2] - box[0] + box[0] : 1);
        scaleY = scaleX;
        offsetY = (size.height - (box[3] - box[1]) * scaleY) / 2;
      }

      // Create paint for the box
      final boxPaint =
          Paint()
            ..color = boxColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0;

      // Create paint for the label background
      final labelBgPaint =
          Paint()
            ..color = boxColor.withOpacity(0.7)
            ..style = PaintingStyle.fill;

      // Scale and draw the box
      final Rect rect = Rect.fromLTRB(
        box[0] * scaleX + offsetX,
        box[1] * scaleY + offsetY,
        box[2] * scaleX + offsetX,
        box[3] * scaleY + offsetY,
      );

      canvas.drawRect(rect, boxPaint);

      // Draw label text
      final textStyle = ui.TextStyle(color: Colors.white, fontSize: 14);

      final paragraphBuilder =
          ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.left))
            ..pushStyle(textStyle)
            ..addText('${label}: ${(score * 100).toInt()}%');

      final paragraph =
          paragraphBuilder.build()..layout(ui.ParagraphConstraints(width: 150));

      // Draw label background
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left,
          rect.top - paragraph.height - 2,
          paragraph.width + 8,
          paragraph.height + 2,
        ),
        labelBgPaint,
      );

      // Draw label text
      canvas.drawParagraph(
        paragraph,
        Offset(rect.left + 4, rect.top - paragraph.height - 2),
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
