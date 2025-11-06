import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

/// Widget compartilhado para captura de fotos com layout moderno e profissional
/// Usado em: cadastro facial, reconhecimento facial, etc.
class CameraPreviewWidget extends StatefulWidget {
  final CameraDescription camera;
  final bool autoCapture;
  final String title;

  const CameraPreviewWidget({
    super.key,
    required this.camera,
    this.autoCapture = false,
    this.title = 'Capturar Rosto',
  });

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget> {
  CameraController? controller;
  bool _tirandoFoto = false;
  bool _disposed = false;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadCamerasAndInitialize();
  }

  Future<void> _loadCamerasAndInitialize() async {
    try {
      _cameras = await availableCameras();

      // Encontrar o índice da câmera passada
      _currentCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == widget.camera.lensDirection,
      );
      if (_currentCameraIndex == -1) _currentCameraIndex = 0;

      await _initializeCamera();
    } catch (e) {
      print('❌ Erro ao carregar câmeras: $e');
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      if (_cameras.isEmpty) return;

      controller = CameraController(
        _cameras[_currentCameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller!.initialize();

      if (mounted && !_disposed) {
        setState(() {});
      }
    } catch (e) {
      print('❌ Erro ao inicializar câmera: $e');
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _trocarCamera() async {
    if (_cameras.length < 2) return;

    setState(() => _tirandoFoto = true);

    try {
      await controller?.dispose();

      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;

      await _initializeCamera();

      setState(() => _tirandoFoto = false);
    } catch (e) {
      print('❌ Erro ao trocar câmera: $e');
      setState(() => _tirandoFoto = false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    controller?.dispose();
    super.dispose();
  }

  Future<void> _tirarFoto() async {
    if (_tirandoFoto || controller == null || !controller!.value.isInitialized) return;

    setState(() => _tirandoFoto = true);

    try {
      final image = await controller!.takePicture();

      if (mounted && !_disposed) {
        Navigator.pop(context, image.path);
      }
    } catch (e) {
      print('❌ Erro ao tirar foto: $e');
      if (mounted && !_disposed) {
        setState(() => _tirandoFoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro ao tirar foto: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: const Color(0xFF4C643C),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                'Inicializando câmera...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // 🎨 Feedback visual
    Color frameColor = Colors.greenAccent;
    String statusMessage = 'Posicione o rosto na moldura';
    IconData statusIcon = Icons.face;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              onPressed: _tirandoFoto ? null : _trocarCamera,
              tooltip: 'Trocar Câmera',
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 📸 CÂMERA PREENCHENDO TODA A TELA (proporção correta, sem distorção)
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller!.value.previewSize!.height,
                height: controller!.value.previewSize!.width,
                child: CameraPreview(controller!),
              ),
            ),
          ),

          // 🎯 Moldura de guia sutil (apenas borda, sem obstruir visão)
          Center(
            child: Container(
              width: 280,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(180),
                border: Border.all(
                  color: Colors.white.withOpacity(0.7),
                  width: 2,
                ),
              ),
            ),
          ),

          // 💬 Feedback de status
          Positioned(
            top: 100,
            left: 16,
            right: 16,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: frameColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        statusMessage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ℹ️ Info da câmera
          if (_cameras.length > 1)
            Positioned(
              top: 160,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    _cameras[_currentCameraIndex].lensDirection == CameraLensDirection.front
                        ? '📷 Câmera Frontal'
                        : '📷 Câmera Traseira',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),

          // 🔄 Overlay de processamento
          if (_tirandoFoto)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                      SizedBox(height: 20),
                      Text(
                        '📸 Capturando foto...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ⚡ Botão de captura manual
          if (!_tirandoFoto)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Column(
                  children: [
                    // Botão principal
                    GestureDetector(
                      onTap: _tirarFoto,
                      child: Container(
                        width: 75,
                        height: 75,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: frameColor,
                            width: 5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: frameColor.withOpacity(0.5),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          size: 35,
                          color: frameColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Toque para capturar',
                        style: TextStyle(
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
      ),
    );
  }
}
