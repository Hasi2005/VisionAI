import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' show join;
// codes taking pictures and sending to flask ml server for now ... change later 
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
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
      title: "Vision AI",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4285F4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4285F4), 
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      themeMode: ThemeMode.system,
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
  String selectedMode = ""; // nothing selected case 
  bool isProcessing = false;
  String? resultText;
  Timer? _liveProcessingTimer;
  //API config ML 
  final String apiUrl = "http://192.168.0.214:5000/predict"; // device flas api endpoint ... currently this .. change if restarted 

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
    _controller.lockCaptureOrientation(DeviceOrientation.portraitUp); // only portrait works
    _initializeControllerFuture = _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }
  
  @override
  void dispose() {
    _stopLiveProcessing();
    _controller.dispose();
    super.dispose();
  }
  void _startLiveProcessing() {
    _liveProcessingTimer?.cancel();//exisiting timer cancelled ? 
    _liveProcessingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) { // every 500 ms captures frame 
      if (!isProcessing && selectedMode.isNotEmpty) {
        _processFrame();
      }
    });
  }
  void _stopLiveProcessing() {
    _liveProcessingTimer?.cancel();
    _liveProcessingTimer = null;
  }
  Future<void> _processFrame() async {
    if (selectedMode.isEmpty) {
      return;
    }
    try {
      setState(() {
        isProcessing = true;
      });
      await _initializeControllerFuture;
      final XFile image = await _controller.takePicture();
      final prediction = await _uploadImageForPrediction(image.path, selectedMode); // uplaoding to server part 
      
      setState(() {
        resultText = prediction;
        isProcessing = false;
      });
      
    } catch (e) {
      setState(() {
        isProcessing = false;
        resultText = "Error: ${e.toString()}";
      });
    }
  }
  
  // flask ml server uploading image for now 
  Future<String> _uploadImageForPrediction(String imagePath, String mode) async {
    final File imageFile = File(imagePath);
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'image': base64Image,
          'mode': mode.toLowerCase() // text/scene sending (look if needed )
        }),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return responseData['prediction'] ?? 'No result found';
      } else {
        return 'Server error: ${response.statusCode}';
      }
    } catch (e) {
      return 'Connection error: ${e.toString()}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "Vision AI",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDarkMode 
                  ? [Colors.black, const Color(0xFF121212)]
                  : [Colors.blue.shade50, Colors.white],
              ),
            ),
          ),
          // cam
          Positioned.fill(
            child: FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  final size = MediaQuery.of(context).size;
                  return Container(
                    width: size.width,
                    height: size.height,
                    padding: const EdgeInsets.only(top: 0, bottom: 100),
                    child: Center(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 15,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Transform.rotate(
                            angle: 90 * (3.1415926535897932 / 180),
                            child: SizedBox(
                              width: size.height,
                              height: size.width,
                              child: ClipRect(
                                child: OverflowBox(
                                  alignment: Alignment.center,
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox(
                                      width: size.height * _controller.value.aspectRatio,
                                      height: size.height,
                                      child: CameraPreview(_controller),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                } else {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          "Initializing camera...",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
          
          
         //loading thing 
          if (isProcessing)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      "loading...",
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

          Align(
            alignment: const Alignment(0.0, 0.85),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode 
                  ? Colors.grey.shade900.withOpacity(0.8)
                  : Colors.grey.shade200.withOpacity(0.8),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedMode = "TEXT";
                            _startLiveProcessing(); // can include toggle maybe ? but woudln't be useful 
                          });
                          print("Text mode selected");
                        },
                        child: Container(
                          width: 120,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: selectedMode == "TEXT" ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selectedMode == "TEXT" 
                                ? Theme.of(context).colorScheme.primary 
                                : Colors.grey.withOpacity(0.5),
                              width: 2,
                            ),
                            boxShadow: selectedMode == "TEXT"
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.text_fields,
                                size: 36,
                                color: selectedMode == "TEXT" 
                                  ? Theme.of(context).colorScheme.primary 
                                  : Theme.of(context).colorScheme.onSurface,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "TEXT",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: selectedMode == "TEXT" 
                                    ? Theme.of(context).colorScheme.primary 
                                    : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedMode = "SCENE";
                            _startLiveProcessing(); // same here 
                          });
                          print("Scene mode selected");
                        },
                        child: Container(
                          width: 120,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: selectedMode == "SCENE" ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selectedMode == "SCENE" 
                                ? Theme.of(context).colorScheme.primary 
                                : Colors.grey.withOpacity(0.5),
                              width: 2,
                            ),
                            boxShadow: selectedMode == "SCENE"
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.photo_camera,
                                size: 36,
                                color: selectedMode == "SCENE" 
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "SCENE",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: selectedMode == "SCENE" 
                                    ? Theme.of(context).colorScheme.primary 
                                    : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
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