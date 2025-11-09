import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:embarqueellus/services/single_face_capture_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Tela de captura única de face para detecção e recorte facial
///
/// Funcionalidades:
/// - Preview da câmera em tempo real
/// - Captura única de foto
/// - Detecção automática de face com ML Kit
/// - Recorte da região facial
/// - Retorno de Uint8List pronto para embeddings
///
/// Compatível com iOS 15.5+ e Android
class FaceCaptureScreen extends StatefulWidget {
  /// Callback chamado quando uma face é capturada com sucesso
  final Function(Uint8List faceImage)? onFaceCaptured;

  /// Se deve usar câmera frontal (padrão: false - câmera traseira)
  final bool useFrontCamera;

  const FaceCaptureScreen({
    super.key,
    this.onFaceCaptured,
    this.useFrontCamera = false,
  });

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  CameraController? _cameraController;
  SingleFaceCaptureService? _captureService;

  bool _isInitializing = true;
  bool _isProcessing = false;
  String? _errorMessage;
  List<CameraDescription>? _cameras;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _captureService = SingleFaceCaptureService();
  }

  /// Inicializa a câmera
  Future<void> _initializeCamera() async {
    try {
      setState(() {
        _isInitializing = true;
        _errorMessage = null;
      });

      // 1. Obtém câmeras disponíveis
      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('Nenhuma câmera disponível no dispositivo');
      }

      // 2. Seleciona câmera (frontal ou traseira)
      final CameraDescription selectedCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection ==
            (widget.useFrontCamera
                ? CameraLensDirection.front
                : CameraLensDirection.back),
        orElse: () => _cameras!.first,
      );

      Sentry.captureMessage(
        '📷 Câmera selecionada: ${selectedCamera.name} (${selectedCamera.lensDirection})',
        level: SentryLevel.info,
      );

      // 3. Configura o controller
      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        // iOS usa BGRA8888, Android usa YUV420 por padrão
        imageFormatGroup: ImageFormatGroup.jpeg, // JPEG é universal e mais simples
      );

      // 4. Inicializa o controller
      await _cameraController!.initialize();

      Sentry.captureMessage(
        '✅ Câmera inicializada com sucesso: ${_cameraController!.value.previewSize}',
        level: SentryLevel.info,
      );

      setState(() {
        _isInitializing = false;
      });
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({'context': 'FaceCaptureScreen._initializeCamera'}),
      );

      setState(() {
        _isInitializing = false;
        _errorMessage = 'Erro ao inicializar câmera: ${e.toString()}';
      });
    }
  }

  /// Captura e processa a face
  Future<void> _captureAndProcessFace() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _showSnackBar('Câmera não está pronta', isError: true);
      return;
    }

    if (_isProcessing) {
      return; // Evita múltiplos processamentos simultâneos
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      Sentry.captureMessage(
        '🚀 Iniciando captura e processamento de face...',
        level: SentryLevel.info,
      );

      // 1. Captura e detecta a face
      final result = await _captureService!.captureAndDetectFace(_cameraController!);

      // 2. Extrai os dados
      final Uint8List faceImage = result['faceImage'] as Uint8List;
      final Rect boundingBox = result['boundingBox'] as Rect;

      Sentry.captureMessage(
        '✅ Face capturada: ${faceImage.lengthInBytes} bytes, região: ${boundingBox.width.toInt()}x${boundingBox.height.toInt()}',
        level: SentryLevel.info,
      );

      // 3. Chama callback se fornecido
      if (widget.onFaceCaptured != null) {
        widget.onFaceCaptured!(faceImage);
      }

      // 4. Retorna o resultado para a tela anterior
      if (mounted) {
        Navigator.of(context).pop({
          'faceImage': faceImage,
          'boundingBox': boundingBox,
          'success': true,
        });
      }
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({'context': 'FaceCaptureScreen._captureAndProcessFace'}),
      );

      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });

      _showSnackBar(_errorMessage!, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// Exibe mensagem ao usuário
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 4 : 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _captureService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Captura Facial'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Mostra loading durante inicialização
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Inicializando câmera...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Mostra erro se houver
    if (_errorMessage != null && _cameraController == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _initializeCamera,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar Novamente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Mostra preview da câmera
    return Stack(
      children: [
        // Preview da câmera
        Positioned.fill(
          child: _buildCameraPreview(),
        ),

        // Overlay com guia de posicionamento
        Positioned.fill(
          child: _buildOverlay(),
        ),

        // Mensagem de instruções
        Positioned(
          top: 40,
          left: 0,
          right: 0,
          child: _buildInstructions(),
        ),

        // Botão de captura
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: _buildCaptureButton(),
        ),

        // Indicador de processamento
        if (_isProcessing) _buildProcessingOverlay(),
      ],
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return CameraPreview(_cameraController!);
  }

  Widget _buildOverlay() {
    return CustomPaint(
      painter: _FaceOvalPainter(),
    );
  }

  Widget _buildInstructions() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.face, color: Colors.white, size: 32),
          const SizedBox(height: 8),
          Text(
            'Posicione seu rosto no centro',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Mantenha boa iluminação e olhe para a câmera',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureButton() {
    return Center(
      child: GestureDetector(
        onTap: _isProcessing ? null : _captureAndProcessFace,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isProcessing ? Colors.grey : Colors.white,
            border: Border.all(
              color: Colors.white,
              width: 4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: _isProcessing
              ? const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
                )
              : const Icon(
                  Icons.camera_alt,
                  color: Colors.black,
                  size: 40,
                ),
        ),
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Processando face...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Por favor, aguarde',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter para desenhar o oval de guia para posicionamento da face
class _FaceOvalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Desenha overlay escuro com buraco oval no centro
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Oval central (70% da largura, posicionado no centro superior)
    final ovalWidth = size.width * 0.7;
    final ovalHeight = ovalWidth * 1.3; // Proporção de rosto
    final ovalLeft = (size.width - ovalWidth) / 2;
    final ovalTop = size.height * 0.25;

    final ovalRect = Rect.fromLTWH(ovalLeft, ovalTop, ovalWidth, ovalHeight);

    path.addOval(ovalRect);
    path.fillType = PathFillType.evenOdd;

    // Desenha overlay escuro
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.5);
    canvas.drawPath(path, overlayPaint);

    // Desenha borda do oval
    canvas.drawOval(ovalRect, paint);

    // Desenha cantos arredondados nos 4 cantos do oval
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;

    // Canto superior esquerdo
    canvas.drawArc(
      Rect.fromLTWH(ovalLeft - 2, ovalTop - 2, cornerLength * 2, cornerLength * 2),
      3.14, // 180 graus
      0.785, // 45 graus
      false,
      cornerPaint,
    );

    // Canto superior direito
    canvas.drawArc(
      Rect.fromLTWH(
          ovalLeft + ovalWidth - cornerLength * 2 + 2, ovalTop - 2, cornerLength * 2, cornerLength * 2),
      4.71, // 270 graus
      0.785, // 45 graus
      false,
      cornerPaint,
    );

    // Canto inferior esquerdo
    canvas.drawArc(
      Rect.fromLTWH(
          ovalLeft - 2, ovalTop + ovalHeight - cornerLength * 2 + 2, cornerLength * 2, cornerLength * 2),
      2.356, // 135 graus
      0.785, // 45 graus
      false,
      cornerPaint,
    );

    // Canto inferior direito
    canvas.drawArc(
      Rect.fromLTWH(ovalLeft + ovalWidth - cornerLength * 2 + 2,
          ovalTop + ovalHeight - cornerLength * 2 + 2, cornerLength * 2, cornerLength * 2),
      0, // 0 graus
      0.785, // 45 graus
      false,
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
