import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' show join;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;
import 'dart:math';
import 'dart:typed_data';
import 'vid_upload.dart';

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
  RTCVideoRenderer? _remoteRenderer;
  Timer? _captionUpdateTimer;
  Timer? _connectionCheckTimer;
  
  // WebRTC properties
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  
  final ImageLabeler _imageLabeler = GoogleMlKit.vision.imageLabeler();
  final TextRecognizer _textRecognizer = GoogleMlKit.vision.textRecognizer();
  final ObjectDetector _objectDetector = GoogleMlKit.vision.objectDetector(
    options: ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    ),
  );
  
  // IP address configuration - update this with your server IP
  final String apiBaseUrl = "http://10.135.60.170:5000"; // Update with your server IP
  
  @override
  void initState() {
    super.initState();
    _initializeCamera(widget.camera);
    _initRenderers();
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
  
  Future<void> _initRenderers() async {
    _remoteRenderer = RTCVideoRenderer();
    await _remoteRenderer!.initialize();
  }
  
  @override
  void dispose() {
    _stopLiveStreaming();
    _stopCaptionGeneration();
    _imageLabeler.close();
    _textRecognizer.close();
    _objectDetector.close();
    _controller.dispose();
    _remoteRenderer?.dispose();
    _connectionCheckTimer?.cancel();
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
          resultText = "Caption error: ${e.toString().substring(0, min(50, e.toString().length))}";
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

  // Updated WebRTC implementation to match Python backend
  Future<void> _createPeerConnection() async {
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"urls": "stun:stun.l.google.com:19302"},
      ]
    };

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": false,
        "OfferToReceiveVideo": true,
      },
      "optional": [],
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (candidate) {
      // Send candidate to server
      _sendIceCandidate(candidate);
    };

    _peerConnection!.onAddStream = (stream) {
      setState(() {
        _remoteRenderer?.srcObject = stream;
      });
    };

    // Get local stream from camera
    final Map<String, dynamic> mediaConstraints = {
      'audio': false,
      'video': {
        'facingMode': 'environment',
        'width': {'ideal': 1280},
        'height': {'ideal': 720}
      }
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // Create offer
    RTCSessionDescription offer = await _peerConnection!.createOffer(offerSdpConstraints);
    await _peerConnection!.setLocalDescription(offer);

    // Send offer to server
    await _sendOffer(offer);
  }

  Future<void> _sendOffer(RTCSessionDescription offer) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/webrtc/offer'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sdp': offer.sdp,
          'type': offer.type,
        }),
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> body = jsonDecode(response.body);
        String sdp = body['sdp'];
        String type = body['type'];
        
        RTCSessionDescription answer = RTCSessionDescription(sdp, type);
        await _peerConnection!.setRemoteDescription(answer);
        
        // Start caption polling
        _startCaptionPolling();
      } else {
        setState(() {
          resultText = "WebRTC setup failed: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        resultText = "WebRTC error: ${e.toString().substring(0, min(50, e.toString().length))}";
      });
    }
  }

  void _sendIceCandidate(RTCIceCandidate candidate) async {
    try {
      await http.post(
        Uri.parse('$apiBaseUrl/webrtc/candidate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }),
      );
    } catch (e) {
      print("Error sending ICE candidate: $e");
    }
  }

  void _startCaptionPolling() {
    _connectionCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      try {
        final response = await http.get(Uri.parse('$apiBaseUrl/api/caption'));
        if (response.statusCode == 200) {
          Map<String, dynamic> body = jsonDecode(response.body);
          setState(() {
            resultText = body['caption'];
          });
        }
      } catch (e) {
        print("Caption polling error: $e");
      }
    });
  }

  // Health check to verify connection to backend
  Future<bool> _checkServerHealth() async {
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/api/health'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  void _startLiveStreaming() async {
    if (isStreaming) return;
    
    setState(() {
      isProcessing = true;
      resultText = "Connecting to AI server...";
    });
    
    // Check server health before attempting connection
    bool isServerHealthy = await _checkServerHealth();
    if (!isServerHealthy) {
      setState(() {
        isProcessing = false;
        resultText = "Error: Cannot connect to AI server. Check server address.";
      });
      return;
    }
    
    setState(() {
      isStreaming = true;
      isProcessing = false;
      resultText = "Starting WebRTC connection...";
    });
    
    await _createPeerConnection();
  }

  void _stopLiveStreaming() {
    _connectionCheckTimer?.cancel();
    
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop());
      _localStream = null;
    }
    
    _peerConnection?.close();
    _peerConnection = null;
    
    setState(() {
      isStreaming = false;
      _remoteRenderer?.srcObject = null;
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
          // Exit button
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
          // Background gradient
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
          
          // Video view - either WebRTC remote stream or camera preview
Positioned.fill(
  child: isStreaming && _remoteRenderer != null
    ? Container(
        padding: const EdgeInsets.only(top: 90, bottom: 150),
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
              child: RTCVideoView(
                _remoteRenderer!,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),
        ),
      )
    : FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            final size = MediaQuery.of(context).size;
            return Container(
              width: size.width,
              height: size.height,
              padding: const EdgeInsets.only(top: 90, bottom: 150),
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
                    child: SizedBox(
                      width: size.height,
                      height: size.width,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: size.width - 40,
                              height: (size.width - 40) * _controller.value.aspectRatio,
                              child: CameraPreview(_controller),
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
          
          // Loading indicator
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

          // Caption display - Updated with better styling
          if (resultText != null)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                margin: EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1.0,
                  ),
                ),
                child: Text(
                  resultText!,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            
          // Control buttons
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
                      // Caption button (replacing Text button)
                      GestureDetector(
                        onTap: () {
                          if (isGeneratingCaptions) {
                            _stopCaptionGeneration();
                          } else {
                            _startCaptionGeneration();
                          }
                        },
                        child: Container(
                          width: 120,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: isGeneratingCaptions ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isGeneratingCaptions
                                ? Theme.of(context).colorScheme.primary 
                                : Colors.grey.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isGeneratingCaptions ? Icons.stop : Icons.subtitles,
                                size: 36,
                                color: isGeneratingCaptions
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isGeneratingCaptions ? "STOP" : "CAPTION",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isGeneratingCaptions
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Stream button
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