import 'dart:async';
import 'dart:io'; // Importante para verificar a plataforma
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
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
  bool _isInitialized = false;
  bool _hasDetected = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        // 🚀 CORREÇÃO 1: Usar o formato nativo correto para Android e iOS
        imageFormatGroup: Platform.isAndroid 
            ? ImageFormatGroup.yuv420 
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController.initialize();

      // Deixamos 'all' para garantir que não ignora nada
      _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.all]);

      await _cameraController.startImageStream(_processCameraImage);

      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      if (kDebugMode) print('Erro ao iniciar câmera: $e');
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || _hasDetected) return;
    _isBusy = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final camera = _cameraController.description;
      
      final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;

      // 🚀 CORREÇÃO 2: Dizer exatamente ao ML Kit qual é o formato que estamos a enviar
      InputImageFormat? inputImageFormat;
      if (Platform.isIOS) {
        inputImageFormat = InputImageFormat.bgra8888;
      } else if (Platform.isAndroid) {
        inputImageFormat = InputImageFormat.nv21; // ML Kit trata o YUV420 do Android como nv21
      }

      if (inputImageFormat == null) {
        _isBusy = false;
        return;
      }

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageData,
      );

      final barcodes = await _barcodeScanner.processImage(inputImage);

      if (barcodes.isNotEmpty) {
        final value = barcodes.first.rawValue;
        if (value != null && value.isNotEmpty) {
          _hasDetected = true;
          widget.onScanned(value);
        }
      }
    } catch (e) {
      if (kDebugMode) print('Erro MLKit: $e');
    }

    // 🚀 CORREÇÃO 3: Pausa de 50ms para permitir que a câmara faça o Auto-Focus
    await Future.delayed(const Duration(milliseconds: 50));
    _isBusy = false;
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4C643C)),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        CameraPreview(_cameraController),
        Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.greenAccent, width: 3),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const Positioned(
          bottom: 40,
          child: Text(
            'Aponte o código dentro da moldura',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              backgroundColor: Colors.black45,
            ),
          ),
        ),
      ],
    );
  }
}
