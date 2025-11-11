import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'native_face_service.dart';
import 'platform_camera_utils.dart';

/// Serviço PRINCIPAL para captura única de foto com detecção facial.
///
/// NOVA ARQUITETURA (Migração Nativa):
/// 1. Inicialização da câmera
/// 2. Captura de uma única foto (não streaming)
/// 3. DELEGAÇÃO para NativeFaceService (processamento nativo iOS/Android)
/// 4. Retorno do recorte como Uint8List pronto para embeddings
///
/// RESPONSABILIDADE ÚNICA:
/// - FaceCaptureService: Apenas gerencia câmera e captura foto
/// - NativeFaceService: Ponte para processamento nativo (correção EXIF + detecção + recorte)
/// - Código Nativo (Swift/Kotlin): Processamento completo usando ML Kit nativo
///
/// BENEFÍCIOS:
/// ✅ Correção de EXIF nativa (UIImage no iOS, ExifInterface no Android)
/// ✅ Detecção facial mais rápida e precisa (SDK nativo do ML Kit)
/// ✅ Resolve completamente o bug do iOS com InputImage.fromFile()
/// ✅ Código modular e testável
/// ✅ Compatível com iOS 15.5+ e Android
///
/// DEPENDÊNCIAS:
/// - NativeFaceService: ponte para processamento nativo
/// - PlatformCameraUtils: utilitários multiplataforma
class FaceCaptureService {
  FaceCaptureService._();

  static final FaceCaptureService instance = FaceCaptureService._();

  final NativeFaceService _nativeService = NativeFaceService.instance;
  final PlatformCameraUtils _platformUtils = PlatformCameraUtils.instance;

  CameraController? _controller;
  bool _isInitialized = false;

  /// Inicializa a câmera para captura.
  ///
  /// [useFrontCamera] - true para câmera frontal, false para traseira
  Future<void> initCamera({bool useFrontCamera = false}) async {
    try {
      await Sentry.captureMessage(
        '📷 FACE_CAPTURE: Inicializando câmera',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
          scope.setContexts('camera_init', {
            'camera_type': useFrontCamera ? 'front' : 'back',
          });
        },
      );

      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('Nenhuma câmera disponível no dispositivo');
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection ==
            (useFrontCamera ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => cameras.first,
      );

      await Sentry.captureMessage(
        '📱 FACE_CAPTURE: Câmera selecionada',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('camera_selected', {
            'camera_name': camera.name,
            'camera_direction': camera.lensDirection.toString(),
            'sensor_orientation': camera.sensorOrientation,
          });
        },
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: _platformUtils.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      _isInitialized = true;

      await Sentry.captureMessage(
        '✅ FACE_CAPTURE: Câmera inicializada com sucesso',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
          scope.setContexts('camera_initialized', {
            'resolution': ResolutionPreset.high.toString(),
            'format': _platformUtils.expectedImageFormat.toString(),
          });
        },
      );
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao inicializar câmera para captura facial',
          'platform': _platformUtils.platformDescription,
        }),
      );
      rethrow;
    }
  }

  /// Captura uma foto, detecta a face e retorna o recorte facial.
  ///
  /// NOVA ARQUITETURA (Migração Nativa):
  /// - FaceCaptureService: Apenas captura a foto
  /// - NativeFaceService: Ponte para código nativo
  /// - Código Nativo (Swift/Kotlin): Corrige EXIF, detecta e recorta usando ML Kit nativo
  ///
  /// Retorna [FaceCaptureResult] contendo:
  /// - croppedFaceBytes: Uint8List da face recortada (pronta para embeddings)
  /// - boundingBox: Coordenadas da face detectada
  /// - imagePath: Caminho da imagem original capturada
  ///
  /// Lança exceção se:
  /// - Câmera não foi inicializada
  /// - Nenhuma face foi detectada
  /// - Erro no processamento
  Future<FaceCaptureResult> captureAndDetectFace() async {
    try {
      if (_controller == null || !_isInitialized) {
        throw Exception('Câmera não foi inicializada. Chame initCamera() primeiro.');
      }

      await Sentry.captureMessage(
        '📸 FACE_CAPTURE: Capturando foto',
        level: SentryLevel.info,
      );

      // PASSO 1: Capturar foto (responsabilidade única do FaceCaptureService)
      final XFile file = await _controller!.takePicture();
      final String imagePath = file.path;

      await Sentry.captureMessage(
        '✅ FACE_CAPTURE: Foto capturada | Delegando processamento para NativeFaceService',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
          scope.setContexts('photo_captured', {
            'image_path': imagePath,
            'file_exists': await File(imagePath).exists(),
          });
        },
      );

      // PASSO 2: Delegar TODO processamento para o código nativo
      // O código nativo agora é responsável por:
      // - Corrigir EXIF automaticamente (UIImage/ExifInterface)
      // - Detectar face usando ML Kit nativo
      // - Recortar face
      // - Redimensionar para 112x112
      // - Converter para JPEG
      final nativeResult = await _nativeService.detectAndCropFace(imagePath);

      await Sentry.captureMessage(
        '✅ FACE_CAPTURE: Captura e processamento concluídos',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
          scope.setContexts('capture_complete', {
            'cropped_bytes_size': nativeResult.croppedFaceBytes.length,
            'bbox_width': nativeResult.boundingBox.width.toInt(),
            'bbox_height': nativeResult.boundingBox.height.toInt(),
          });
        },
      );

      return FaceCaptureResult(
        croppedFaceBytes: nativeResult.croppedFaceBytes,
        boundingBox: nativeResult.boundingBox,
        imagePath: imagePath,
      );
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao capturar e detectar face',
          'platform': _platformUtils.platformDescription,
        }),
      );
      rethrow;
    }
  }

  /// Retorna o CameraController para prévia da câmera na UI.
  CameraController? get controller => _controller;

  /// Verifica se a câmera está inicializada.
  bool get isInitialized => _isInitialized;

  /// Libera recursos da câmera.
  Future<void> dispose() async {
    try {
      await _controller?.dispose();
      _controller = null;
      _isInitialized = false;

      await Sentry.captureMessage(
        '🗑️ FACE_CAPTURE: Recursos da câmera liberados',
        level: SentryLevel.info,
      );
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao liberar recursos da câmera',
        }),
      );
    }
  }

  /// Retorna a rotação da imagem baseada na câmera e orientação.
  InputImageRotation getRotation({
    DeviceOrientation orientation = DeviceOrientation.portraitUp,
  }) {
    if (_controller == null) {
      return InputImageRotation.rotation0deg;
    }

    return _platformUtils.getImageRotation(
      camera: _controller!.description,
      deviceOrientation: orientation,
    );
  }
}

/// Resultado da captura facial.
class FaceCaptureResult {
  /// Bytes da face recortada (JPEG, 112x112) - pronta para gerar embeddings
  final Uint8List croppedFaceBytes;

  /// Coordenadas da bounding box da face na imagem original
  final Rect boundingBox;

  /// Caminho da imagem original capturada
  final String imagePath;

  const FaceCaptureResult({
    required this.croppedFaceBytes,
    required this.boundingBox,
    required this.imagePath,
  });

  @override
  String toString() {
    return 'FaceCaptureResult('
        'croppedFaceBytes: ${croppedFaceBytes.length} bytes, '
        'boundingBox: ${boundingBox.width.toInt()}x${boundingBox.height.toInt()}, '
        'imagePath: $imagePath'
        ')';
  }
}
