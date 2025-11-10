import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'face_detection_service.dart';
import 'face_image_processor.dart';
import 'platform_camera_utils.dart';

/// Serviço para captura única de foto com detecção facial.
///
/// Este serviço implementa o fluxo completo de:
/// 1. Inicialização da câmera
/// 2. Captura de uma única foto (não streaming)
/// 3. Detecção facial via Google ML Kit
/// 4. Recorte da face detectada
/// 5. Retorno do recorte como Uint8List pronto para embeddings
///
/// Compatível com iOS 15.5+ e Android.
class FaceCaptureService {
  FaceCaptureService._();

  static final FaceCaptureService instance = FaceCaptureService._();

  final FaceDetectionService _detection = FaceDetectionService.instance;
  final FaceImageProcessor _processor = FaceImageProcessor.instance;
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

      // 1. Capturar foto
      final XFile file = await _controller!.takePicture();
      final String imagePath = file.path;

      await Sentry.captureMessage(
        '✅ FACE_CAPTURE: Foto capturada',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('photo_captured', {
            'image_path': imagePath,
            'file_exists': await File(imagePath).exists(),
          });
        },
      );

      // 2. Criar InputImage para detecção
      final inputImage = InputImage.fromFilePath(imagePath);

      await Sentry.captureMessage(
        '🔍 FACE_CAPTURE: Detectando faces na imagem',
        level: SentryLevel.info,
      );

      // 3. Detectar faces
      final faces = await _detection.detect(inputImage);

      if (faces.isEmpty) {
        await Sentry.captureMessage(
          '❌ FACE_CAPTURE: Nenhuma face detectada',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('detection_result', 'no_faces');
            scope.setContexts('detection_failed', {
              'image_path': imagePath,
            });
          },
        );

        throw Exception('Nenhum rosto detectado na imagem. Por favor, posicione seu rosto na câmera.');
      }

      await Sentry.captureMessage(
        '✅ FACE_CAPTURE: Face(s) detectada(s)',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('faces_detected', {
            'total_faces': faces.length,
            'primary_face_bbox': '${faces.first.boundingBox.width.toInt()}x${faces.first.boundingBox.height.toInt()}',
          });
        },
      );

      final primaryFace = faces.first;

      await Sentry.captureMessage(
        '✂️ FACE_CAPTURE: Recortando face',
        level: SentryLevel.info,
      );

      // 4. Recortar face e converter para Uint8List
      final Uint8List croppedFaceBytes = await _processor.cropFaceToBytes(
        imagePath,
        outputSize: 112,
      );

      await Sentry.captureMessage(
        '✅ FACE_CAPTURE: Captura e processamento concluídos',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
          scope.setContexts('capture_complete', {
            'cropped_bytes_size': croppedFaceBytes.length,
            'bbox_width': primaryFace.boundingBox.width.toInt(),
            'bbox_height': primaryFace.boundingBox.height.toInt(),
          });
        },
      );

      return FaceCaptureResult(
        croppedFaceBytes: croppedFaceBytes,
        boundingBox: primaryFace.boundingBox,
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
