import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class BarcodeCameraView extends StatefulWidget {
  final Function(String) onScanned;
  const BarcodeCameraView({super.key, required this.onScanned});

  @override
  State<BarcodeCameraView> createState() => _BarcodeCameraViewState();
}

class _BarcodeCameraViewState extends State<BarcodeCameraView> {
  late CameraController _cameraController;
  late BarcodeScanner _barcodeScanner;
  bool _isBusy = false;
  CameraImage? _cameraImage;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode, BarcodeFormat.code128]);
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    _cameraController = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
    await _cameraController.initialize();

    _cameraController.startImageStream((image) async {
      if (_isBusy) return;
      _isBusy = true;
      _cameraImage = image;

      try {
        final inputImage = _convertToInputImage(image, _cameraController.description);
        final barcodes = await _barcodeScanner.processImage(inputImage);
        if (barcodes.isNotEmpty) {
          final value = barcodes.first.rawValue;
          if (value != null && value.isNotEmpty) {
            widget.onScanned(value);
          }
        }
      } catch (e) {
        debugPrint('Erro MLKit: $e');
      }

      _isBusy = false;
    });

    if (mounted) setState(() {});
  }

  InputImage _convertToInputImage(CameraImage image, CameraDescription camera) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
    final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;
    final planeData = image.planes.map((plane) {
      return InputImagePlaneMetadata(bytesPerRow: plane.bytesPerRow, height: plane.height, width: plane.width);
    }).toList();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(size: imageSize, rotation: imageRotation, format: inputImageFormat, bytesPerRow: planeData.first.bytesPerRow),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraController.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return CameraPreview(_cameraController);
  }
}
