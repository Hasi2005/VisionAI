import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
//import 'package:flutter/rendering.dart';
//import 'package:provider/provider.dart';

// i had to manually go and change the settings.gradel files version to get rid of the error that was happening and 
//some other gradle file for the camera to runn...
// please ensure u do that all the time .. also if u make a camera udate ... dont hot reload ... rerun flutter 
// check for camera 

void main() async{
  // Ensure that plugin services are initialized so that `availableCameras()`
// can be called before `runApp()
WidgetsFlutterBinding.ensureInitialized();
final cameras= await availableCameras();
final firstCamera=cameras.first;
   runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
   final CameraDescription camera; // for camera 
  const MyApp({super.key,required this.camera}); // constructor ... ensures that camera is provided when myapp is instantiated 
  @override
  Widget build(BuildContext context) {
    return MaterialApp( // helpful with scaffolding 
      debugShowCheckedModeBanner: false,
      title: "Welcome to Vision AI",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), // seedcolor .. overall theme: blue 
        useMaterial3: true, // Enables Material Design 3
      ),
      home: HomePage(camera: camera),
    );
  }
}

class HomePage extends StatefulWidget {
  final CameraDescription camera;
   const HomePage({super.key, required this.camera});// doing the same for the stateful widget 
  //const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late CameraController _controller; //<HHERE: Added CameraController>
  late Future<void> _initializeControllerFuture; 
  // to see which button is selected 
   bool isTextSelected = false;  
  bool isSceneSelected = false; 
  @override
  void initState(){ // please check spellings 
    super.initState();
    // Initialize the camera controller.
    _controller = CameraController(
      widget.camera, //<HHERE: Use the camera passed to the widget>
      ResolutionPreset.high ,
    );

    // Initialize the controller.
    _initializeControllerFuture = _controller.initialize();
  }
   @override
  void dispose() {
    // Dispose of the controller when the widget is disposed.
    _controller.dispose(); //<HHERE: Dispose of CameraController>
    super.dispose();
  }
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vision AI"),
        centerTitle: true,
      ),
      body: Stack(
        //mainAxisSize: MainAxisSize.min, // spaces it out 
        children: [
          // camera... 
           FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return CameraPreview(_controller); 
              } else {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }
            },
          ),
          //const Spacer(),
    Align(
      alignment: Alignment(0.0, 0.85), // Move the buttons slightly to the left and near the bottom
  child: Padding(
    padding: const EdgeInsets.only(bottom: 40),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // iconButton for Text icon
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    //const Text("Text", style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 8), // Space between text and icon
                    ElevatedButton(
                      onPressed: (){
                        setState(() {
                          isTextSelected = true; 
                          isSceneSelected = false;
                        });
                        print("text_icon pressed ");
                      } ,
                      style: ElevatedButton.styleFrom(
                        fixedSize: const Size(120, 120), // Set both width and height
                        backgroundColor: isTextSelected ? Colors.blue : null,
                        foregroundColor: isTextSelected ? Colors.white : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8), // Rounded corners
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("TEXT"), // Text appears above the icon
                          const SizedBox(height: 8), // Space between text and icon
                          Icon(Icons.text_fields, size: 40,color: isTextSelected ? Colors.white : null,),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 40),
                // IconButton for person iconm 
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    //const Text("Scene", style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 8), // Space between text and icon
                    ElevatedButton(
                      //icon: const Icon(Icons.person, size: 40),
                      onPressed:(){
                        setState(() {
                          isTextSelected = false; 
                          isSceneSelected = true; 
                        });
                        print("person icon pressed ");
                      }, // Call the function when pressed
                      //label:Text("SCENE"),
                      style: ElevatedButton.styleFrom(
                        fixedSize: const Size(120, 120), // Set both width and height
                        backgroundColor: isSceneSelected ? Colors.blue : null,
                        foregroundColor: isSceneSelected ? Colors.white : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8), // Rounded corners
                        ),
                      ),
                       child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children:  [
                          Text("SCENE"), // Text appears above the icon
                          SizedBox(height: 8), // Space between text and icon
                          Icon(Icons.person, size: 40,color: isSceneSelected ? Colors.white : null,),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
    ),
          const SizedBox(height: 40), // Space at the bottom if necessary
        ],
      ),
    );
  }
}
