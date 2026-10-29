import 'dart:async';
import 'dart:io';
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
  CameraController? _cameraController;
  BarcodeScanner? _barcodeScanner;
  Timer? _cooldownTimer;
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
      if (cameras.isEmpty || !mounted) return;

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      _cameraController = controller;

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      // Inclui todos os formatos usados por QR e pulseiras
      _barcodeScanner = BarcodeScanner(
        formats: [
          BarcodeFormat.qrCode,
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.code93,
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upca,
          BarcodeFormat.upce,
          BarcodeFormat.itf,
          BarcodeFormat.codabar,
        ],
      );

      await controller.startImageStream(_processCameraImage);

      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      if (kDebugMode) print('Erro ao iniciar câmera: $e');
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final controller = _cameraController;
    final scanner = _barcodeScanner;
    if (_isBusy || _hasDetected || controller == null || scanner == null) return;
    _isBusy = true;

    try {
      if (kDebugMode) {
        print('📸 Formato capturado: ${image.format.raw}');
      }

      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }

      final bytes = allBytes.done().buffer.asUint8List();
      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());

      final camera = controller.description;
      final imageRotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;

      final inputImageFormat = _resolveImageFormat(image.format.raw);
      if (inputImageFormat == null) {
        if (kDebugMode) {
          print('⚠️ Formato não suportado: ${image.format.raw}');
        }
        _isBusy = false;
        return;
      }

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final barcodes = await scanner.processImage(inputImage);

      if (barcodes.isNotEmpty) {
        final value = barcodes.first.rawValue;
        if (value != null && value.isNotEmpty) {
          _hasDetected = true;
          widget.onScanned(value);
          // Caso o QR Code seja inválido e a tela continue aberta, libera nova leitura após 2s
          _cooldownTimer?.cancel();
          _cooldownTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) {
              _hasDetected = false;
            }
          });
        }
      }
    } catch (e) {
      if (kDebugMode) print('Erro MLKit: $e');
    }

    _isBusy = false;
  }

  InputImageFormat? _resolveImageFormat(int rawFormat) {
    switch (rawFormat) {
      case 35:
      case 17:
        return InputImageFormat.nv21;
      case 1111970369:
        return InputImageFormat.bgra8888;
      case 256:
      case 34:
        return InputImageFormat.nv21;
      default:
        return null;
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _cameraController?.dispose();
    _barcodeScanner?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    if (!_isInitialized || controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4C643C)),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        CameraPreview(controller),
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
