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
import 'package:embarqueellus/config/app_config.dart';

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
  bool _isCapturingBurst = false;
  bool _isSwitchingCamera = false;
  String? _errorMessage;
  String _statusMessage = '';

  // Para modo de cadastro em rajada (1 toque -> N fotos)
  int _currentCaptureIndex = 0;
  final List<String> _capturedImagePaths = [];
  final List<img.Image> _processedImages = [];

  int get _totalCaptures =>
      widget.options.captureCount ?? widget.mode.captureCount;

  bool get _isBurstEnrollment =>
      widget.mode != CameraMode.recognition && _totalCaptures > 1;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      await FaceRecognitionService.instance.init();
      if (AppConfig.instance.sentryFacialVerboseLogs) {
        await Sentry.captureMessage(
          '✅ Serviços de reconhecimento facial inicializados',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setTag('screen', 'unified_face_camera');
            scope.setTag('mode', widget.mode.name);
          },
        );
      }
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

      if (AppConfig.instance.sentryFacialVerboseLogs) {
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
      }
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

      if (AppConfig.instance.sentryFacialVerboseLogs) {
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
      }

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

    // Modo de cadastro em rajada: 1 único toque dispara as 3 fotos sequencialmente
    if (_isBurstEnrollment) {
      await _captureBurstEnrollment();
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Capturando foto...';
    });

    try {
      final XFile image = await _cameraController!.takePicture();

      if (AppConfig.instance.sentryFacialVerboseLogs) {
        await Sentry.captureMessage(
          '📸 Foto capturada',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setContexts('capture', {
              'path': image.path,
              'mode': widget.mode.name,
              'capture_index': _currentCaptureIndex + 1,
              'total_captures': _totalCaptures,
            });
          },
        );
      }

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

  /// Dispara automaticamente `N` fotos em sequência com 1 único toque no botão,
  /// atualizando o contador na tela (`1/3 fotos`, `2/3 fotos`, `3/3 fotos`) e
  /// processando os recortes faciais em seguida.
  Future<void> _captureBurstEnrollment() async {
    final total = _totalCaptures;

    setState(() {
      _isProcessing = true;
      _isCapturingBurst = true;
      _currentCaptureIndex = 0;
      _capturedImagePaths.clear();
      _processedImages.clear();
      _statusMessage = 'Mantenha firme... Capturando 1/$total fotos';
    });

    try {
      // 1. Disparar as N fotos sequencialmente mantendo o preview visível
      for (int i = 0; i < total; i++) {
        if (!mounted ||
            _cameraController == null ||
            !_cameraController!.value.isInitialized) {
          break;
        }

        if (i > 0) {
          setState(() {
            _statusMessage = 'Mantenha firme... Capturando ${i + 1}/$total fotos';
          });
        }

        final XFile shot = await _cameraController!.takePicture();
        _capturedImagePaths.add(shot.path);

        if (mounted) {
          setState(() {
            _currentCaptureIndex = i + 1;
            _statusMessage = '${i + 1}/$total fotos capturadas';
          });
        }

        if (i < total - 1) {
          await Future.delayed(widget.options.burstDelay);
        }
      }

      // Breve pausa para o monitor visualizar "3/3 fotos" antes da tela de processamento
      await Future.delayed(const Duration(milliseconds: 200));

      if (!mounted) return;
      setState(() {
        _isCapturingBurst = false;
        _statusMessage = 'Processando $_currentCaptureIndex/$total fotos...';
      });

      // 2. Detectar e recortar cada foto nativamente (garantindo limpeza dos temporários)
      try {
        for (int i = 0; i < _capturedImagePaths.length; i++) {
          final path = _capturedImagePaths[i];
          if (mounted) {
            setState(() {
              _statusMessage = 'Validando rosto (${i + 1}/$total fotos)...';
            });
          }

          try {
            final nativeResult =
                await NativeFaceService.instance.detectAndCropFace(path);
            final decoded = img.decodeImage(nativeResult.croppedFaceBytes);
            if (decoded != null) {
              _processedImages.add(decoded);
            }
          } catch (shotError) {
            print(
              '⚠️ [Rajada] Foto ${i + 1}/$total sem rosto válido detectado: $shotError',
            );
          } finally {
            await _deleteTempFile(path);
          }
        }
      } finally {
        for (final path in _capturedImagePaths) {
          await _deleteTempFile(path);
        }
      }

      if (_processedImages.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '❌ Nenhum rosto detectado nas $total fotos. Posicione o rosto no guia e tente novamente.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
          setState(() {
            _isProcessing = false;
            _isCapturingBurst = false;
            _currentCaptureIndex = 0;
            _statusMessage = '';
          });
        }
        return;
      }

      await Sentry.captureMessage(
        '✅ Rajada de cadastro concluída: ${_processedImages.length}/$total fotos válidas',
        level: SentryLevel.info,
      );

      final result = FaceCameraResult.enrollment(
        imagePaths: List<String>.from(_capturedImagePaths),
        processedImages: List<img.Image>.from(_processedImages),
      );

      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e, stackTrace) {
      for (final path in _capturedImagePaths) {
        await _deleteTempFile(path);
      }

      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao capturar rajada de fotos faciais',
          'mode': widget.mode.name,
        }),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro na captura em rajada: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isProcessing = false;
          _isCapturingBurst = false;
          _currentCaptureIndex = 0;
          _statusMessage = '';
        });
      }
    }
  }

  Future<void> _deleteTempFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }

  Future<void> _processCapture(String imagePath) async {
    try {
      setState(() => _statusMessage = 'Detectando rosto...');

      // 1. Detectar e processar face nativamente (iOS/Android)
      // MIGRAÇÃO: Agora usa NativeFaceService que corrige EXIF e detecta nativamente
      final NativeFaceResult nativeResult;
      try {
        nativeResult = await NativeFaceService.instance.detectAndCropFace(imagePath);
      } finally {
        // Remove o arquivo temporário bruto do disco assim que o recorte 112x112 em memória é obtido
        await _deleteTempFile(imagePath);
      }

      if (AppConfig.instance.sentryFacialVerboseLogs) {
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
      }

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
          if (AppConfig.instance.sentryFacialVerboseLogs) {
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
          }

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

        // Loading overlay (apenas após concluir os disparos da rajada)
        if (_isProcessing && !_isCapturingBurst) _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildFaceGuide() {
    final borderColor = _isCapturingBurst
        ? const Color(0xFF4CAF50)
        : Colors.white.withOpacity(0.5);
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 250,
        height: 300,
        decoration: BoxDecoration(
          border: Border.all(
            color: borderColor,
            width: _isCapturingBurst ? 3.5 : 2,
          ),
          borderRadius: BorderRadius.circular(150),
        ),
      ),
    );
  }

  Widget _buildTopOverlay() {
    final total = _totalCaptures;
    final showBurstCounter =
        widget.mode.isMultiCapture && widget.options.showCaptureCounter && total > 1;

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
              Colors.black.withOpacity(0.75),
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
            if (showBurstCounter) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _currentCaptureIndex > 0
                      ? const Color(0xFF4C643C)
                      : Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isCapturingBurst
                        ? const Color(0xFF81C784)
                        : Colors.white38,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  _currentCaptureIndex == 0 && !_isCapturingBurst
                      ? '📸 0/$total fotos (1 toque = $total disparos)'
                      : '📸 $_currentCaptureIndex/$total fotos',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(total, (index) {
                  final stepNumber = index + 1;
                  final isTaken = _currentCaptureIndex >= stepNumber;
                  final isCurrent = _isCapturingBurst &&
                      _currentCaptureIndex + 1 == stepNumber;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isTaken
                            ? const Color(0xFF4CAF50)
                            : (isCurrent
                                ? Colors.amber.shade700
                                : Colors.white.withOpacity(0.18)),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isTaken || isCurrent
                              ? Colors.white
                              : Colors.white38,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isTaken
                                ? Icons.check_circle
                                : (isCurrent
                                    ? Icons.camera_alt
                                    : Icons.radio_button_unchecked),
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$stepNumber/$total',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _statusMessage,
                  style: const TextStyle(
                    color: Colors.yellowAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final total = _totalCaptures;
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
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isCapturingBurst
                      ? const Color(0xFF4C643C)
                      : (_isProcessing ? Colors.grey : Colors.white),
                  border: Border.all(color: Colors.white, width: 3),
                ),
                alignment: Alignment.center,
                child: _isCapturingBurst
                    ? Text(
                        '$_currentCaptureIndex/$total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : Icon(
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
