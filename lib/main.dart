import 'package:flutter/material.dart';
//import 'package:flutter/rendering.dart';
//import 'package:provider/provider.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key}); // constructor 
  @override
  Widget build(BuildContext context) {
    return MaterialApp( // helpful with scaffolding 
      debugShowCheckedModeBanner: false,
      title: "Welcome to Vision AI",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), // seedcolor .. overall theme: blue 
        useMaterial3: true, // Enables Material Design 3
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // to see which button is selected 
   bool isTextSelected = false;  
  bool isSceneSelected = false; 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vision AI"),
        centerTitle: true,
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min, // spaces it out 
        children: [
          const Spacer(),
          Row(
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
                        Text("TEXT"), // Text appears above the icon
                        SizedBox(height: 8), // Space between text and icon
                        Icon(Icons.text_fields, size: 40,color: isTextSelected ? Colors.white : null,),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 40),
              // IconButton for Person icon
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
          const SizedBox(height: 80), // Space at the bottom if necessary
        ],
      ),
    );
  }
}
