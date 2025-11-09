import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Widget de câmera para capturar foto do rosto.
///
/// 🎯 PADRÃO: Câmera traseira (melhor qualidade)
/// Usa formato JPEG universal para captura única (compatível iOS 15.5+ e Android)
class FaceCameraView extends StatefulWidget {
  final Function(XFile) onCapture;
  final bool useFrontCamera;

  const FaceCameraView({
    super.key,
    required this.onCapture,
    this.useFrontCamera = false, // 🎯 PADRÃO: câmera traseira
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

      // 🎯 Selecionar câmera (traseira por padrão para melhor qualidade)
      final selectedCamera = widget.useFrontCamera
          ? cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      )
          : cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // 📱 Formato JPEG para captura única (universal iOS/Android)
      // ⚠️ IMPORTANTE para iOS 15.5+:
      // - BGRA8888 funciona apenas para STREAMING (startImageStream)
      // - Para takePicture(), sempre usa JPEG independente do imageFormatGroup
      // - Usar JPEG diretamente evita problemas de rotação e metadados EXIF
      // - É o formato mais confiável para captura única em ambas plataformas
      final imageFormat = ImageFormatGroup.jpeg;

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: imageFormat,
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
      fit: StackFit.expand,
      children: [
        // 📸 Preview da câmera em TELA CHEIA
        Positioned.fill(
          child: CameraPreview(_cameraController!),
        ),

        // Moldura oval para o rosto
        Center(
          child: Container(
            width: 300,
            height: 380,
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(190),
              border: Border.all(
                color: Colors.greenAccent,
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.greenAccent.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),

        // Instruções
        Positioned(
          top: 100,
          left: 16,
          right: 16,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.9),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.face, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Posicione o rosto na moldura',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Botão de captura
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: Column(
              children: [
                // Botão principal de captura
                GestureDetector(
                  onTap: _isCapturing ? null : _capturePhoto,
                  child: Container(
                    width: 75,
                    height: 75,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isCapturing ? Colors.grey : Colors.white,
                      border: Border.all(
                        color: const Color(0xFF4C643C),
                        width: 5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4C643C).withOpacity(0.5),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
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
                            size: 35,
                            color: Color(0xFF4C643C),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

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
        ),
      ],
    );
  }
}