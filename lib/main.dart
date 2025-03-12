import 'package:camera_tflite/bounding_box_painter.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final cameras = await availableCameras();

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

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

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isFrontCamera = false;
  bool _isProcessing = false;
  double _processingProgress = 0.0;
  File? _capturedImage;
  List<Map<String, dynamic>>? _detections;
  late TFLiteHelper _tfLite;

  @override
  void initState() {
    super.initState();
    _initializeCamera(widget.cameras[0]);
    _tfLite = TFLiteHelper();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      await _tfLite.loadModel();
    } catch (e) {
      debugPrint('Error loading model: $e');
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
    _tfLite.dispose();
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    final CameraDescription newCamera =
        _isFrontCamera ? widget.cameras[0] : widget.cameras[1];

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
        _processingProgress = 0.0;
      });

      await _processImage();

      setState(() {
        _isProcessing = false;
      });
    } catch (e) {
      debugPrint('Error capturing image: $e');
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _processImage() async {
    if (_capturedImage == null) return;

    try {
      for (int i = 1; i <= 5; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        setState(() {
          _processingProgress = i / 5;
        });
      }

      final detections = await _tfLite.processImage(_capturedImage!);

      if (mounted) {
        setState(() {
          _detections = detections;
          _processingProgress = 1.0;
        });
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
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
                    CameraPreview(_controller),
                    Positioned(
                      bottom: 30,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (widget.cameras.length > 1)
                            IconButton(
                              icon: const Icon(Icons.flip_camera_ios),
                              color: Colors.white,
                              iconSize: 32,
                              onPressed: _toggleCamera,
                            ),

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
                      Image.file(_capturedImage!, fit: BoxFit.contain),

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
