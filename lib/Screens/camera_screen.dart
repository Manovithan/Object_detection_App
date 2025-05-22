import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_v2/tflite_v2.dart';
import 'result_screen.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool isModelLoaded = false;
  List<dynamic>? recognitions;
  int imageHeight = 0;
  int imageWidth = 0;
  bool _isSheetExpanded = true;
  bool _navigatedToResult = false;

  @override
  void initState() {
    super.initState();
    loadModel();
    initializeCamera(null);
  }

  @override
  void dispose() {
    _controller.dispose();
    Tflite.close();
    super.dispose();
  }

  Future<void> loadModel() async {
    String? res = await Tflite.loadModel(
      model: 'assets/detect.tflite',
      labels: 'assets/labelmap.txt',
    );
    setState(() {
      isModelLoaded = res != null;
    });
  }

  void toggleCamera() {
    final lensDirection = _controller.description.lensDirection;
    CameraDescription newDescription;
    if (lensDirection == CameraLensDirection.front) {
      newDescription = widget.cameras.firstWhere((description) =>
      description.lensDirection == CameraLensDirection.back);
    } else {
      newDescription = widget.cameras.firstWhere((description) =>
      description.lensDirection == CameraLensDirection.front);
    }
    initializeCamera(newDescription);
  }

  void initializeCamera(CameraDescription? description) async {
    if (description == null) {
      _controller = CameraController(
        widget.cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
      );
    } else {
      _controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
      );
    }

    await _controller.initialize();

    if (!mounted) return;

    _controller.startImageStream((CameraImage image) {
      if (isModelLoaded && !_navigatedToResult) {
        runModel(image);
      }
    });

    setState(() {});
  }

  void runModel(CameraImage image) async {
    if (image.planes.isEmpty) return;

    var results = await Tflite.detectObjectOnFrame(
      bytesList: image.planes.map((plane) => plane.bytes).toList(),
      model: 'SSDMobileNet',
      imageHeight: image.height,
      imageWidth: image.width,
      imageMean: 127.5,
      imageStd: 127.5,
      numResultsPerClass: 1,
      threshold: 0.4,
    );

    if (results!.isNotEmpty && !_navigatedToResult) {
      var topDetection = results.firstWhere(
            (res) => res['confidenceInClass'] > 0.7,
        orElse: () => null,
      );

      if (topDetection != null) {
        _navigatedToResult = true;
        await _controller.stopImageStream();
        XFile imageFile = await _controller.takePicture();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ResultScreen(
              imagePath: imageFile.path,
              objectData: Map<String, dynamic>.from(topDetection),
              cameras: widget.cameras,
            ),
          ),
        );
      }
    }

    setState(() {
      recognitions = results;
      imageHeight = image.height;
      imageWidth = image.width;
    });
  }

  void _toggleSheet() {
    setState(() {
      _isSheetExpanded = !_isSheetExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final highConfidenceDetections = (recognitions != null)
        ? recognitions!.where((rec) => rec["confidenceInClass"] > 0.8).toList()
        : [];

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.purple,
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(30),
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Real-time Object Detection'),
            actions: [
              IconButton(
                icon: const Icon(Icons.cameraswitch),
                onPressed: toggleCamera,
                tooltip: 'Toggle Camera',
              ),
            ],
          ),
        ),
      ),

      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(
                width: screenWidth,
                height: screenHeight * 0.85,
                child: Stack(
                  children: [
                    CameraPreview(_controller),
                    if (recognitions != null)
                      BoundingBoxes(
                        recognitions: recognitions!,
                        previewH: imageHeight.toDouble(),
                        previewW: imageWidth.toDouble(),
                        screenH: screenHeight * 0.8,
                        screenW: screenWidth,
                      ),
                  ],
                ),
              ),
            ],
          ),

          // if (highConfidenceDetections.isNotEmpty)
          //   Align(
          //     alignment: Alignment.bottomCenter,
          //     child: AnimatedContainer(
          //       duration: const Duration(milliseconds: 300),
          //       height: _isSheetExpanded ? 160 : 64,
          //       padding: EdgeInsets.only(
          //         left: 16,
          //         right: 16,
          //         top: 8,
          //         bottom: MediaQuery.of(context).padding.bottom + 8,
          //       ),
          //       decoration: BoxDecoration(
          //         color: Colors.purple[100],
          //         borderRadius:
          //         const BorderRadius.vertical(top: Radius.circular(20)),
          //         boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
          //       ),
          //       child: Column(
          //         crossAxisAlignment: CrossAxisAlignment.start,
          //         children: [
          //           Row(
          //             mainAxisAlignment: MainAxisAlignment.spaceBetween,
          //             children: [
          //               const Text(
          //                 'Object Details',
          //                 style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          //               ),
          //               IconButton(
          //                 icon: Icon(_isSheetExpanded
          //                     ? Icons.expand_more
          //                     : Icons.expand_less),
          //                 onPressed: _toggleSheet,
          //                 tooltip: _isSheetExpanded ? 'Collapse' : 'Expand',
          //               ),
          //               // IconButton(
          //               //   icon: const Icon(Icons.cameraswitch),
          //               //   onPressed: toggleCamera,
          //               //   tooltip: 'Toggle Camera',
          //               // ),
          //             ],
          //           ),
          //           if (_isSheetExpanded) ...[
          //             const SizedBox(height: 8),
          //             const Text(
          //               "Objects Detected (Confidence > 70%):",
          //               style:
          //               TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          //             ),
          //             const SizedBox(height: 6),
          //             Expanded(
          //               child: ListView.builder(
          //                 itemCount: highConfidenceDetections.length,
          //                 itemBuilder: (context, index) {
          //                   var obj = highConfidenceDetections[index];
          //                   return Text(
          //                     "• ${obj["detectedClass"]} - ${(obj["confidenceInClass"] * 100).toStringAsFixed(2)}%",
          //                   );
          //                 },
          //               ),
          //             ),
          //           ],
          //         ],
          //       ),
          //     ),
          //   ),
        ],
      ),
    );
  }
}

class BoundingBoxes extends StatelessWidget {
  final List<dynamic> recognitions;
  final double previewH;
  final double previewW;
  final double screenH;
  final double screenW;

  const BoundingBoxes({
    Key? key,
    required this.recognitions,
    required this.previewH,
    required this.previewW,
    required this.screenH,
    required this.screenW,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: recognitions.map((rec) {
        var x = rec["rect"]["x"] * screenW;
        var y = rec["rect"]["y"] * screenH;
        double w = rec["rect"]["w"] * screenW;
        double h = rec["rect"]["h"] * screenH;

        return Positioned(
          left: x,
          top: y,
          width: w,
          height: h,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red, width: 3),
            ),
            child: Text(
              "${rec["detectedClass"]} ${(rec["confidenceInClass"] * 100).toStringAsFixed(0)}%",
              style: const TextStyle(
                color: Colors.red,
                fontSize: 15,
                backgroundColor: Colors.black,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
