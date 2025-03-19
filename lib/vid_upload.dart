import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';

class VideoUploadPage extends StatefulWidget {
  const VideoUploadPage({super.key});

  @override
  State<VideoUploadPage> createState() => _VideoUploadPageState();
}

class _VideoUploadPageState extends State<VideoUploadPage> {
  File? _selectedVideo;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _uploadResult;
  VideoPlayerController? _videoController;

  // API config - updated to match main.dart
  final String apiBaseUrl = "http://10.135.60.170:5000";

  Future<void> _pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      if (_videoController != null) {
        await _videoController!.dispose();
        _videoController = null;
      }

      setState(() {
        _selectedVideo = File(result.files.first.path!);
        _uploadResult = null;
      });

      // Initialize video player
      _videoController = VideoPlayerController.file(_selectedVideo!)
        ..initialize().then((_) {
          // Ensure the first frame is shown
          setState(() {});
        });
    }
  }

  Future<void> _uploadVideo() async {
    if (_selectedVideo == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
      _uploadResult = "Uploading video...";
    });

    try {
      // Create multipart request
      final uri = Uri.parse('$apiBaseUrl/api/upload_video');
      final request = http.MultipartRequest('POST', uri);
      
      // Add file to request
      final fileStream = http.ByteStream(_selectedVideo!.openRead());
      final fileLength = await _selectedVideo!.length();
      
      final multipartFile = http.MultipartFile(
        'video',
        fileStream,
        fileLength,
        filename: path.basename(_selectedVideo!.path),
      );
      
      request.files.add(multipartFile);
      
      // Track upload progress
      final streamedResponse = await request.send();
      
      // Listen for progress updates
      streamedResponse.stream.listen(
        (List<int> bytes) {
          final progress = bytes.length / fileLength;
          setState(() {
            _uploadProgress = progress;
          });
        },
        onDone: () async {
          final response = await http.Response.fromStream(streamedResponse);
          
          setState(() {
            _isUploading = false;
            if (response.statusCode == 200) {
              try {
                Map<String, dynamic> jsonResponse = {};
                try {
                  jsonResponse = Map<String, dynamic>.from(
                    json.decode(response.body) as Map,
                  );
                } catch (e) {
                  // Handle JSON parsing error
                }
                
                _uploadResult = jsonResponse['message'] ?? "Upload successful!";
              } catch (e) {
                _uploadResult = "Upload successful!";
              }
            } else {
              _uploadResult = "Upload failed: ${response.statusCode}";
            }
          });
        },
        onError: (error) {
          setState(() {
            _isUploading = false;
            _uploadResult = "Error uploading: $error";
          });
        },
      );
    } catch (e) {
      setState(() {
        _isUploading = false;
        _uploadResult = "Error: ${e.toString()}";
      });
    }
  }
  
  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "Video Upload",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
          
          // Main content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Video preview area
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: _selectedVideo == null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.video_file,
                                    size: 60,
                                    color: isDarkMode
                                        ? Colors.white.withOpacity(0.6)
                                        : Colors.grey.shade600,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    "No video selected",
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: isDarkMode
                                          ? Colors.white.withOpacity(0.6)
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: _videoController != null &&
                                      _videoController!.value.isInitialized
                                  ? Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        AspectRatio(
                                          aspectRatio:
                                              _videoController!.value.aspectRatio,
                                          child: VideoPlayer(_videoController!),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            _videoController!.value.isPlaying
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                            size: 50,
                                            color: Colors.white.withOpacity(0.8),
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _videoController!.value.isPlaying
                                                  ? _videoController!.pause()
                                                  : _videoController!.play();
                                            });
                                          },
                                        ),
                                      ],
                                    )
                                  : const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                            ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Upload status and progress
                  if (_uploadResult != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? Colors.grey.shade900
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _uploadResult!,
                            style: TextStyle(
                              color: isDarkMode
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                          if (_isUploading) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: _uploadProgress,
                              backgroundColor: Colors.grey.withOpacity(0.3),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "${(_uploadProgress * 100).toStringAsFixed(0)}%",
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  
                  // Action buttons
                  Row(
                    children: [
                      // Select video button
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.video_library),
                          label: const Text("SELECT VIDEO"),
                          onPressed: _isUploading ? null : _pickVideo,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Upload button
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.cloud_upload),
                          label: const Text("UPLOAD"),
                          onPressed: (_selectedVideo != null && !_isUploading)
                              ? _uploadVideo
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
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