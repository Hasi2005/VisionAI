import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For DeviceOrientation

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();

  // Filter the cameras to use only the back camera
  final backCamera = cameras.firstWhere(
    (camera) => camera.lensDirection == CameraLensDirection.back,
  );

  runApp(MyApp(camera: backCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;
  const MyApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Welcome to Vision AI",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: HomePage(camera: camera),
    );
  }
}

class HomePage extends StatefulWidget {
  final CameraDescription camera;
  const HomePage({super.key, required this.camera});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool isTextSelected = false;
  bool isSceneSelected = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera(widget.camera);
  }

  void _initializeCamera(CameraDescription camera) {
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
    );

    // Lock the camera orientation to portrait
    _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vision AI"),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                // Ensure the camera preview is displayed vertically
                return Center(
                  child: Transform.rotate(
                    angle: 90 * (3.1415926535897932 / 180), // Rotate 90 degrees
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: CameraPreview(_controller),
                    ),
                  ),
                );
              } else {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }
            },
          ),
          Align(
            alignment: Alignment(0.0, 0.85),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            isTextSelected = true;
                            isSceneSelected = false;
                          });
                          print("text_icon pressed ");
                        },
                        style: ElevatedButton.styleFrom(
                          fixedSize: const Size(120, 120),
                          backgroundColor: isTextSelected ? Colors.blue : null,
                          foregroundColor: isTextSelected ? Colors.white : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("TEXT"),
                            const SizedBox(height: 8),
                            Icon(Icons.text_fields, size: 40, color: isTextSelected ? Colors.white : null),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 40),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            isTextSelected = false;
                            isSceneSelected = true;
                          });
                          print("person icon pressed ");
                        },
                        style: ElevatedButton.styleFrom(
                          fixedSize: const Size(120, 120),
                          backgroundColor: isSceneSelected ? Colors.blue : null,
                          foregroundColor: isSceneSelected ? Colors.white : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("SCENE"),
                            const SizedBox(height: 8),
                            Icon(Icons.person, size: 40, color: isSceneSelected ? Colors.white : null),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}