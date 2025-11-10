import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart' show Rect;

import '../services/face_capture_service.dart';

/// Tela de captura facial usando o FaceCaptureService.
///
/// Demonstra o uso completo do serviço de captura única de foto
/// com detecção e recorte facial automático.
///
/// Fluxo:
/// 1. Inicializa a câmera ao carregar a tela
/// 2. Mostra preview da câmera
/// 3. Usuário pressiona botão para capturar
/// 4. Detecta face, recorta e retorna resultado
class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({super.key});

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  final FaceCaptureService _captureService = FaceCaptureService.instance;

  bool _isLoading = false;
  String? _errorMessage;
  Uint8List? _capturedFaceBytes;
  Rect? _boundingBox;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _captureService.initCamera(useFrontCamera: false);
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao inicializar câmera: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _capturePhoto() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _capturedFaceBytes = null;
    });

    try {
      final result = await _captureService.captureAndDetectFace();

      setState(() {
        _capturedFaceBytes = result.croppedFaceBytes;
        _boundingBox = result.boundingBox;
        _imagePath = result.imagePath;
        _isLoading = false;
      });

      // Aqui você pode usar os bytes da face para gerar embeddings
      print('✅ Face capturada com sucesso!');
      print('📊 Bytes: ${result.croppedFaceBytes.length}');
      print('📐 BoundingBox: ${result.boundingBox.width.toInt()}x${result.boundingBox.height.toInt()}');
      print('📁 Caminho: ${result.imagePath}');

      // Mostrar dialog de sucesso
      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Face Capturada!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_capturedFaceBytes != null)
              Image.memory(
                _capturedFaceBytes!,
                width: 112,
                height: 112,
              ),
            const SizedBox(height: 16),
            Text('Tamanho: ${_capturedFaceBytes?.length ?? 0} bytes'),
            if (_boundingBox != null)
              Text(
                'BBox: ${_boundingBox!.width.toInt()}x${_boundingBox!.height.toInt()}',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Captura Facial'),
        backgroundColor: Colors.blue,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeCamera,
              child: const Text('Tentar Novamente'),
            ),
          ],
        ),
      );
    }

    if (_isLoading && !_captureService.isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Inicializando câmera...'),
          ],
        ),
      );
    }

    if (!_captureService.isInitialized || _captureService.controller == null) {
      return const Center(
        child: Text('Câmera não disponível'),
      );
    }

    return Stack(
      children: [
        // Preview da câmera
        Positioned.fill(
          child: CameraPreview(_captureService.controller!),
        ),

        // Overlay com guia de posicionamento
        Positioned.fill(
          child: CustomPaint(
            painter: FaceGuidePainter(),
          ),
        ),

        // Instruções
        Positioned(
          top: 40,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black54,
            child: const Text(
              'Posicione seu rosto dentro do círculo',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
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
            child: _isLoading
                ? const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  )
                : FloatingActionButton(
                    onPressed: _capturePhoto,
                    backgroundColor: Colors.blue,
                    child: const Icon(
                      Icons.camera_alt,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),

        // Exibir resultado se houver
        if (_capturedFaceBytes != null)
          Positioned(
            top: 100,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.green, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.memory(
                _capturedFaceBytes!,
                width: 80,
                height: 80,
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _captureService.dispose();
    super.dispose();
  }
}

/// Painter para desenhar guia de posicionamento do rosto
class FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.35;

    // Desenhar círculo guia
    canvas.drawCircle(center, radius, paint);

    // Desenhar linhas de referência
    paint.strokeWidth = 1;
    paint.color = Colors.white.withOpacity(0.3);

    // Linha horizontal
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      paint,
    );

    // Linha vertical
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
