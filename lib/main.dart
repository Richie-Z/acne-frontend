import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:saver_gallery/saver_gallery.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  bool _isSaving = false;
  double _processingProgress = 0.0;
  File? _capturedImage;
  Uint8List? _resultImageBytes;
  int _detectionCount = 0;
  String _apiUrl = 'http://10.0.35.97:5200';
  String? _savedImagePath;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeCamera(widget.cameras[0]);
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
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    if (widget.cameras.length < 2) return;

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
        _savedImagePath = null;
      });

      await _processImage(_capturedImage!);
    } catch (e) {
      debugPrint('Error capturing image: $e');
      setState(() {
        _isProcessing = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error capturing image: $e')));
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile != null) {
        setState(() {
          _capturedImage = File(pickedFile.path);
          _isProcessing = true;
          _processingProgress = 0.0;
          _savedImagePath = null;
        });

        await _processImage(_capturedImage!);
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      setState(() {
        _isProcessing = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  Future<void> _processImage(File imageFile) async {
    try {
      // Simulate processing stages with progress
      for (int i = 1; i <= 5; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          setState(() {
            _processingProgress = i / 5;
          });
        }
      }

      // Read image file as bytes
      final bytes = await imageFile.readAsBytes();

      // Encode as base64
      final base64Image = base64Encode(bytes);

      // Send to API
      final response = await http.post(
        Uri.parse('$_apiUrl/predict_base64'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);

        if (result.containsKey('result_image')) {
          setState(() {
            _resultImageBytes = base64Decode(result['result_image']);
            _detectionCount = result['count'] ?? 0;
            _isProcessing = false;
            _processingProgress = 1.0;
          });
        } else {
          throw Exception('Invalid response from server');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error processing image: $e')));

      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _saveImage() async {
    if (_resultImageBytes == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Get the temporary directory
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/acne_detection_$timestamp.jpg';

      // Save the image to a file
      final File imageFile = File(path);
      await imageFile.writeAsBytes(_resultImageBytes!);

      // Save to gallery
      final success = await SaverGallery.saveImage(
        _resultImageBytes!,
        fileName: 'acne_detection_$timestamp.jpg',
        skipIfExists: false,
      );

      setState(() {
        _isSaving = false;
        _savedImagePath = imageFile.path;
      });

      if (success == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Image saved to gallery')));
      } else {
        throw Exception('Failed to save to gallery');
      }
    } catch (e) {
      debugPrint('Error saving image: $e');
      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving image: $e')));
    }
  }

  Future<void> _shareImage() async {
    if (_resultImageBytes == null) return;

    try {
      // Create a temporary file if we don't have a saved path
      String filePath;
      if (_savedImagePath != null) {
        filePath = _savedImagePath!;
      } else {
        final directory = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        filePath = '${directory.path}/acne_detection_$timestamp.jpg';

        // Save the image to a file
        final File imageFile = File(filePath);
        await imageFile.writeAsBytes(_resultImageBytes!);
      }

      // Share the image
      await Share.shareXFiles(
        [XFile(filePath)],
        text:
            'Acne Detection Results: Found $_detectionCount ${_detectionCount == 1 ? 'issue' : 'issues'}',
      );
    } catch (e) {
      debugPrint('Error sharing image: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sharing image: $e')));
    }
  }

  void _resetCamera() {
    setState(() {
      _capturedImage = null;
      _resultImageBytes = null;
      _detectionCount = 0;
      _savedImagePath = null;
    });
  }

  void _updateApiUrl() {
    showDialog(
      context: context,
      builder: (context) {
        String newUrl = _apiUrl;

        return AlertDialog(
          title: const Text('Update API URL'),
          content: TextField(
            decoration: const InputDecoration(
              hintText: 'Enter API URL',
              helperText: 'Example: http://192.168.1.100:5000',
            ),
            onChanged: (value) {
              newUrl = value;
            },
            controller: TextEditingController(text: _apiUrl),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                setState(() {
                  _apiUrl = newUrl;
                });
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acne Detection'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _updateApiUrl,
          ),
        ],
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

                          IconButton(
                            icon: const Icon(Icons.photo_library),
                            color: Colors.white,
                            iconSize: 32,
                            onPressed: _pickImage,
                          ),
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
                  : _resultImageBytes != null
                  ? Image.memory(_resultImageBytes!, fit: BoxFit.contain)
                  : Image.file(_capturedImage!, fit: BoxFit.contain),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              if (_resultImageBytes != null && !_isProcessing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Found: $_detectionCount ${_detectionCount == 1 ? 'issue' : 'issues'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('New Capture'),
                    onPressed: _resetCamera,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  if (_resultImageBytes != null && !_isProcessing)
                    ElevatedButton.icon(
                      icon:
                          _isSaving
                              ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                              )
                              : Icon(
                                _savedImagePath != null
                                    ? Icons.check
                                    : Icons.save,
                              ),
                      label: Text(
                        _savedImagePath != null ? 'Saved' : 'Save Image',
                      ),
                      onPressed:
                          _isSaving || _savedImagePath != null
                              ? null
                              : _saveImage,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  if (_resultImageBytes != null && !_isProcessing)
                    IconButton(
                      icon: const Icon(Icons.share),
                      onPressed: _shareImage,
                      tooltip: 'Share Image',
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
