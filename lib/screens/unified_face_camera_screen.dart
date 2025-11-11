import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:embarqueellus/models/camera_mode.dart';
import 'package:embarqueellus/models/face_camera_options.dart';
import 'package:embarqueellus/models/face_camera_result.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/native_face_service.dart';

/// Tela unificada de câmera facial
///
/// Suporta 3 modos:
/// - enrollment: Cadastro simples (1 foto)
/// - enrollmentAdvanced: Cadastro avançado (3 fotos)
/// - recognition: Reconhecimento facial
class UnifiedFaceCameraScreen extends StatefulWidget {
  final CameraMode mode;
  final FaceCameraOptions options;

  const UnifiedFaceCameraScreen({
    super.key,
    required this.mode,
    this.options = const FaceCameraOptions(),
  });

  @override
  State<UnifiedFaceCameraScreen> createState() => _UnifiedFaceCameraScreenState();
}

class _UnifiedFaceCameraScreenState extends State<UnifiedFaceCameraScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;

  bool _isInitializing = true;
  bool _isProcessing = false;
  bool _isSwitchingCamera = false;
  String? _errorMessage;
  String _statusMessage = '';

  // Para modo avançado
  int _currentCaptureIndex = 0;
  final List<String> _capturedImagePaths = [];
  final List<img.Image> _processedImages = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      await FaceRecognitionService.instance.init();
      await Sentry.captureMessage(
        '✅ Serviços de reconhecimento facial inicializados',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('screen', 'unified_face_camera');
          scope.setTag('mode', widget.mode.name);
        },
      );
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao inicializar serviços de reconhecimento',
          'mode': widget.mode.name,
        }),
      );
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();

      print('📷 Câmeras disponíveis: ${_cameras.length}');
      for (var i = 0; i < _cameras.length; i++) {
        print('  [$i] ${_cameras[i].name} - ${_cameras[i].lensDirection}');
      }

      if (_cameras.isEmpty) {
        setState(() {
          _errorMessage = 'Nenhuma câmera disponível';
          _isInitializing = false;
        });
        return;
      }

      // Selecionar câmera inicial
      _currentCameraIndex = _cameras.indexWhere(
        (c) => widget.options.useFrontCamera
            ? c.lensDirection == CameraLensDirection.front
            : c.lensDirection == CameraLensDirection.back,
      );
      if (_currentCameraIndex == -1) _currentCameraIndex = 0;

      print('📷 Câmera selecionada: [${_currentCameraIndex}] ${_cameras[_currentCameraIndex].name}');

      await _setupCamera(_cameras[_currentCameraIndex]);

      await Sentry.captureMessage(
        '📱 Câmera inicializada com sucesso',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', Platform.isIOS ? 'iOS' : 'Android');
          scope.setContexts('camera_info', {
            'total_cameras': _cameras.length,
            'selected_camera': _cameras[_currentCameraIndex].name,
            'lens_direction': _cameras[_currentCameraIndex].lensDirection.toString(),
          });
        },
      );
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao inicializar câmera',
          'platform': Platform.isIOS ? 'iOS' : 'Android',
        }),
      );

      setState(() {
        _errorMessage = 'Erro ao acessar câmera: $e';
        _isInitializing = false;
      });
    }
  }

  Future<void> _setupCamera(CameraDescription camera) async {
    _cameraController?.dispose();

    _cameraController = CameraController(
      camera,
      widget.options.resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _cameraController!.initialize();

    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length <= 1 || _isSwitchingCamera) {
      print('⚠️ Não é possível trocar câmera: ${_cameras.length} câmera(s) disponível(is)');
      return;
    }

    setState(() => _isSwitchingCamera = true);

    try {
      final previousIndex = _currentCameraIndex;
      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;

      print('🔄 Trocando câmera: ${_cameras[previousIndex].name} -> ${_cameras[_currentCameraIndex].name}');

      await _setupCamera(_cameras[_currentCameraIndex]);

      await Sentry.captureMessage(
        '🔄 Câmera trocada',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('camera_switch', {
            'previous_camera': _cameras[previousIndex].name,
            'new_camera': _cameras[_currentCameraIndex].name,
            'lens_direction': _cameras[_currentCameraIndex].lensDirection.toString(),
          });
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Câmera trocada: ${_cameras[_currentCameraIndex].lensDirection == CameraLensDirection.front ? "Frontal" : "Traseira"}'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ Erro ao trocar câmera: $e');

      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao trocar câmera',
          'cameras_available': _cameras.length,
        }),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao trocar câmera: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSwitchingCamera = false);
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Capturando foto...';
    });

    try {
      final XFile image = await _cameraController!.takePicture();

      await Sentry.captureMessage(
        '📸 Foto capturada',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('capture', {
            'path': image.path,
            'mode': widget.mode.name,
            'capture_index': _currentCaptureIndex + 1,
            'total_captures': widget.mode.captureCount,
          });
        },
      );

      await _processCapture(image.path);
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao capturar foto',
          'mode': widget.mode.name,
        }),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao capturar foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }

      setState(() => _isProcessing = false);
    }
  }

  Future<void> _processCapture(String imagePath) async {
    try {
      setState(() => _statusMessage = 'Detectando rosto...');

      // 1. Detectar e processar face nativamente (iOS/Android)
      // MIGRAÇÃO: Agora usa NativeFaceService que corrige EXIF e detecta nativamente
      final nativeResult = await NativeFaceService.instance.detectAndCropFace(imagePath);

      await Sentry.captureMessage(
        '✅ Face detectada e processada nativamente',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('mode', widget.mode.name);
          scope.setTag('capture_index', '${_currentCaptureIndex + 1}');
          scope.setContexts('native_result', {
            'bytes_size': nativeResult.croppedFaceBytes.length,
            'bbox_width': nativeResult.boundingBox.width.toInt(),
            'bbox_height': nativeResult.boundingBox.height.toInt(),
          });
        },
      );

      // 2. Converter bytes para img.Image (necessário para FaceRecognitionService)
      setState(() => _statusMessage = 'Processando imagem...');

      final decodedImage = img.decodeImage(nativeResult.croppedFaceBytes);
      if (decodedImage == null) {
        throw Exception('Falha ao decodificar imagem processada nativamente');
      }

      // 3. Modo de reconhecimento
      if (widget.mode == CameraMode.recognition) {
        setState(() => _statusMessage = 'Reconhecendo...');

        final recognitionResult = await FaceRecognitionService.instance.recognize(decodedImage);

        if (recognitionResult != null) {
          await Sentry.captureMessage(
            '✅ Reconhecimento bem-sucedido',
            level: SentryLevel.info,
            withScope: (scope) {
              scope.setContexts('recognition', {
                'person_name': recognitionResult['nome'],
                'person_cpf': recognitionResult['cpf'],
                'confidence': recognitionResult['similarity_score'],
                'distance': recognitionResult['distance_l2'],
              });
            },
          );

          final result = FaceCameraResult.recognition(
            recognizedPerson: recognitionResult,
            confidenceScore: recognitionResult['similarity_score'] ?? 0.0,
            distance: recognitionResult['distance_l2'] ?? 999.0,
            imagePath: imagePath,
            processedImage: decodedImage,
          );

          if (mounted) {
            Navigator.pop(context, result);
          }
        } else {
          await Sentry.captureMessage(
            '⚠️ Nenhum aluno reconhecido',
            level: SentryLevel.warning,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ Nenhum aluno reconhecido'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          }

          setState(() => _isProcessing = false);
        }
        return;
      }

      // 4. Modo de cadastro
      _capturedImagePaths.add(imagePath);
      _processedImages.add(decodedImage);
      _currentCaptureIndex++;

      await Sentry.captureMessage(
        '✅ Captura ${_currentCaptureIndex}/${widget.mode.captureCount} processada',
        level: SentryLevel.info,
      );

      // Se completou todas as capturas
      if (_currentCaptureIndex >= widget.mode.captureCount) {
        final result = FaceCameraResult.enrollment(
          imagePaths: _capturedImagePaths,
          processedImages: _processedImages,
        );

        if (mounted) {
          Navigator.pop(context, result);
        }
      } else {
        // Mais capturas necessárias
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Captura ${_currentCaptureIndex}/${widget.mode.captureCount} concluída!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 1),
            ),
          );
        }

        setState(() => _isProcessing = false);
      }
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao processar captura',
          'mode': widget.mode.name,
          'image_path': imagePath,
        }),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao processar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }

      setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.options.title ?? widget.mode.defaultTitle;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, FaceCameraResult.cancelled()),
        ),
        actions: [
          if (widget.options.showCameraSwitchButton && _cameras.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: _isSwitchingCamera
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.flip_camera_ios,
                        size: 28,
                      ),
                tooltip: 'Trocar câmera',
                onPressed: (_isProcessing || _isSwitchingCamera) ? null : _switchCamera,
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Inicializando câmera...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Preview da câmera
        if (_cameraController?.value.isInitialized == true)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.width * _cameraController!.value.aspectRatio,
              child: CameraPreview(_cameraController!),
            ),
          ),

        // Overlay de guia facial
        if (widget.options.showFaceGuide) _buildFaceGuide(),

        // Status e instruções
        _buildTopOverlay(),

        // Controles inferiores
        _buildBottomControls(),

        // Loading overlay
        if (_isProcessing) _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildFaceGuide() {
    return Center(
      child: Container(
        width: 250,
        height: 300,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
          borderRadius: BorderRadius.circular(150),
        ),
      ),
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          children: [
            if (widget.options.subtitle != null)
              Text(
                widget.options.subtitle!,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            if (widget.mode.isMultiCapture && widget.options.showCaptureCounter)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Captura ${_currentCaptureIndex + 1}/${widget.mode.captureCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _statusMessage,
                  style: const TextStyle(color: Colors.yellow, fontSize: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Botão de captura
            GestureDetector(
              onTap: _isProcessing ? null : _capturePhoto,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isProcessing ? Colors.grey : Colors.white,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: _isProcessing ? Colors.white : Colors.black,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
