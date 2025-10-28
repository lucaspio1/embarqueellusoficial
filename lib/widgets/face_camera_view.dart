import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Widget de câmera para capturar foto do rosto
/// Usa o mesmo sistema que o QR Code (que já funciona!)
class FaceCameraView extends StatefulWidget {
  final Function(XFile) onCapture;
  final bool useFrontCamera;

  const FaceCameraView({
    super.key,
    required this.onCapture,
    this.useFrontCamera = true,
  });

  @override
  State<FaceCameraView> createState() => _FaceCameraViewState();
}

class _FaceCameraViewState extends State<FaceCameraView> {
  CameraController? _cameraController;
  bool _isInitialized = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();

      final selectedCamera = widget.useFrontCamera
          ? cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      )
          : cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      print('❌ Erro ao iniciar câmera: $e');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao acessar câmera: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing || _cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final XFile photo = await _cameraController!.takePicture();
      widget.onCapture(photo);
    } catch (e) {
      print('❌ Erro ao capturar foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao capturar foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4C643C)),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // Preview da câmera
        CameraPreview(_cameraController!),

        // Moldura oval para o rosto
        Center(
          child: Container(
            width: 280,
            height: 350,
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(180),
              border: Border.all(
                color: Colors.greenAccent,
                width: 3,
              ),
            ),
          ),
        ),

        // Instruções
        const Positioned(
          top: 60,
          child: Card(
            color: Colors.black54,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Posicione o rosto dentro da moldura',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),

        // Botão de captura
        Positioned(
          bottom: 40,
          child: Column(
            children: [
              // Botão principal de captura
              GestureDetector(
                onTap: _isCapturing ? null : _capturePhoto,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isCapturing
                        ? Colors.grey
                        : Colors.white,
                    border: Border.all(
                      color: const Color(0xFF4C643C),
                      width: 4,
                    ),
                  ),
                  child: _isCapturing
                      ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(
                      color: Color(0xFF4C643C),
                      strokeWidth: 3,
                    ),
                  )
                      : const Icon(
                    Icons.camera_alt,
                    size: 40,
                    color: Color(0xFF4C643C),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Texto do botão
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isCapturing ? 'Capturando...' : 'Toque para capturar',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}