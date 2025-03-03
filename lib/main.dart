import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' show join;
import 'package:web_socket_channel/io.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;
import 'dart:math';
import 'dart:typed_data';
import 'vid_upload.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final backCamera = cameras.firstWhere(
    (camera) => camera.lensDirection == CameraLensDirection.back,
    orElse: () => cameras.first,
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
  String selectedMode = ""; 
  bool isProcessing = false;
  bool isStreaming = false;
  bool isGeneratingCaptions = false;
  String? resultText;
  Image? streamImage;
  Timer? _streamUpdateTimer;
  Timer? _captionUpdateTimer;
  
  final ImageLabeler _imageLabeler = GoogleMlKit.vision.imageLabeler();
  final TextRecognizer _textRecognizer = GoogleMlKit.vision.textRecognizer();
  final ObjectDetector _objectDetector = GoogleMlKit.vision.objectDetector(
    options: ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    ),
  );
  final String apiBaseUrl = "https://vision-ai-backend-yr0v.onrender.com"; // deployed on render .. not working 
  final String streamUrl = "https://vision-ai-backend-yr0v.onrender.com/api/stream"; // Stream endpoint
  
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
    _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    _initializeControllerFuture = _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }
  
  @override
  void dispose() {
    _stopLiveStreaming();
    _stopCaptionGeneration();
    _imageLabeler.close();
    _textRecognizer.close();
    _objectDetector.close();
    _controller.dispose();
    super.dispose();
  }

  void _startCaptionGeneration() {
    if (isGeneratingCaptions) return;
    
    setState(() {
      isGeneratingCaptions = true;
      resultText = "Caption generation started";
    });
    
    _captionUpdateTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) async {
      if (!isGeneratingCaptions) {
        timer.cancel();
        return;
      }
      
      try {
        XFile imageFile = await _controller.takePicture();
        final inputImage = InputImage.fromFilePath(imageFile.path);
        final labels = await _imageLabeler.processImage(inputImage);
        final recognizedText = await _textRecognizer.processImage(inputImage);
        final detectedObjects = await _objectDetector.processImage(inputImage);
        StringBuffer captionBuffer = StringBuffer("I see: ");
        if (labels.isNotEmpty) {
          List<String> labelTexts = labels
              .take(3)
              .map((label) => "${label.label} (${(label.confidence * 100).toStringAsFixed(0)}%)")
              .toList();
          captionBuffer.write(labelTexts.join(", "));
        }
        if (detectedObjects.isNotEmpty) {
          captionBuffer.write(". Objects: ");
          List<String> objectTexts = detectedObjects
              .take(3)
              .map((obj) => "${obj.labels.first.text}")
              .toList();
          captionBuffer.write(objectTexts.join(", "));
        }
        if (recognizedText.text.isNotEmpty) {
          String shortText = recognizedText.text.length > 50 
              ? "${recognizedText.text.substring(0, 50)}..." 
              : recognizedText.text;
          captionBuffer.write(". Text: \"$shortText\"");
        }
        
        setState(() {
          resultText = captionBuffer.toString();
        });
        File(imageFile.path).deleteSync();
        
      } catch (e) {
        setState(() {
          resultText = "Caption error: ${e.toString().substring(0, 50)}";
        });
      }
    });
  }
  
  void _stopCaptionGeneration() {
    _captionUpdateTimer?.cancel();
    _captionUpdateTimer = null;
    
    setState(() {
      isGeneratingCaptions = false;
      resultText = "Caption generation stopped";
    });
  }

 
void _startLiveStreaming() {
  if (isStreaming) return;
  
  setState(() {
    isStreaming = true;
    resultText = "Streaming started - connecting to server...";
  });
  
  
  _streamUpdateTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) async {
    if (!isStreaming) {
      timer.cancel();
      return;
    }
    
    try {
     
      XFile imageFile = await _controller.takePicture();
      File file = File(imageFile.path);
      
      var request = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/api/send_frame'));
      request.files.add(
        await http.MultipartFile.fromPath('image', file.path)
      );
      
      var streamResponse = await request.send();
      if (streamResponse.statusCode == 200) {
        var responseData = await streamResponse.stream.bytesToString();
        Map<String, dynamic> jsonResponse = jsonDecode(responseData);
        if (jsonResponse.containsKey('caption')) {
          setState(() {
            resultText = jsonResponse['caption'];
          });
        }
      } else {
        setState(() {
          resultText = "Error: Server returned ${streamResponse.statusCode}";
        });
      }
      
     
      setState(() {
        
        streamImage = Image.network(
          '$streamUrl?t=${DateTime.now().millisecondsSinceEpoch}',
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            return child;
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Text(
                "Stream connection error. Retrying...",
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            );
          },
        );
      });
      
     
      await file.delete();
      
    } catch (e) {
      setState(() {
        resultText = "Error: ${e.toString().substring(0, min(50, e.toString().length))}";
      });
    }
  });
}

void _stopLiveStreaming() {
  _streamUpdateTimer?.cancel();
  _streamUpdateTimer = null;
 
  try {
    http.get(Uri.parse('$apiBaseUrl/api/health'));
  } catch (e) {
    // ignore 
  }
  
  setState(() {
    isStreaming = false;
    streamImage = null;
    resultText = "Streaming stopped";
  });
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
       
actions: [
  // Video upload button
  IconButton(
    icon: Icon(Icons.file_upload, color: Colors.white),
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const VideoUploadPage()),
      );
    },
    tooltip: "Upload Video",
  ),
  //  exit button
  IconButton(
    icon: Icon(Icons.exit_to_app, color: Colors.white),
    onPressed: () {
      if (isGeneratingCaptions) {
        _stopCaptionGeneration();
      } else if (isStreaming) {
        _stopLiveStreaming();
      }
    },
    tooltip: "Stop",
  ),
],
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
          
          
          Positioned.fill(
            child: isStreaming 
              ? (streamImage ?? Container(
                  color: Colors.black,
                  child: const Center(
                    child: Text(
                      "Connecting to stream...",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ))
              : FutureBuilder<void>(
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
          
          // Loading 
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

          
          if (resultText != null)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.all(8),
                margin: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  resultText!,
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
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
                          // nothing doing 
                          setState(() {
                            resultText = "Text button is disabled";
                          });
                          // auto clearing happening after 2 seconds 
                          Timer(Duration(seconds: 2), () {
                            if (mounted) {
                              setState(() {
                                resultText = null;
                              });
                            }
                          });
                        },
                        child: Container(
                          width: 120,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.text_fields,
                                size: 36,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "TEXT",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // toggling live stream 
                      GestureDetector(
                        onTap: () {
                          if (isStreaming) {
                            _stopLiveStreaming();
                          } else {
                            setState(() {
                              selectedMode = "STREAM";
                            });
                            _startLiveStreaming();
                          }
                        },
                        child: Container(
                          width: 120,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: isStreaming ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isStreaming 
                                ? Theme.of(context).colorScheme.primary 
                                : Colors.grey.withOpacity(0.5),
                              width: 2,
                            ),
                            boxShadow: isStreaming
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
                                isStreaming ? Icons.stop : Icons.video_camera_back,
                                size: 36,
                                color: isStreaming 
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isStreaming ? "STOP" : "STREAM",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isStreaming 
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