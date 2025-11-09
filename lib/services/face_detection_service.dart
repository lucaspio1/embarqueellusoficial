import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'platform_camera_utils.dart';

/// Singleton responsável por detectar rostos utilizando o Google MLKit.
///
/// A implementação mantém uma única instância do [FaceDetector] configurada
/// para o modo FAST, habilitando landmarks, classificação e tracking – conforme
/// requisitos de produção.
class FaceDetectionService {
  FaceDetectionService._();

  static final FaceDetectionService instance = FaceDetectionService._();

  FaceDetector? _faceDetector;
  final PlatformCameraUtils _platformUtils = PlatformCameraUtils.instance;

  FaceDetector _ensureDetector() {
    if (_faceDetector != null) return _faceDetector!;

    debugPrint('\n[🔧 FaceDetection] Inicializando FaceDetector...');
    debugPrint('[🔧 FaceDetection] Plataforma: ${_platformUtils.platformDescription}');
    debugPrint('[🔧 FaceDetection] Modo: FAST');
    debugPrint('[🔧 FaceDetection] Landmarks: HABILITADO');
    debugPrint('[🔧 FaceDetection] Classification: HABILITADO');
    debugPrint('[🔧 FaceDetection] Tracking: HABILITADO\n');

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: true,
      ),
    );
    return _faceDetector!;
  }

  /// Detecta rostos em uma [InputImage].
  Future<List<Face>> detect(InputImage image) async {
    try {
      debugPrint('[👁️ FaceDetection] Iniciando detecção de rostos...');
      debugPrint('[👁️ FaceDetection] Tamanho da imagem: ${image.metadata?.size}');
      debugPrint('[👁️ FaceDetection] Rotação: ${image.metadata?.rotation}');
      debugPrint('[👁️ FaceDetection] Formato: ${image.metadata?.format}');

      final detector = _ensureDetector();
      final stopwatch = Stopwatch()..start();
      final faces = await detector.processImage(image);
      stopwatch.stop();

      debugPrint('[👁️ FaceDetection] Detecção concluída em ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('[👁️ FaceDetection] ${faces.length} rosto(s) detectado(s)');

      if (faces.isEmpty) {
        debugPrint('[⚠️ FaceDetection] Nenhuma face encontrada!');
        await Sentry.captureMessage(
          'Nenhuma face detectada na imagem',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('face_detection', 'no_faces_found');
            scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
            scope.setContexts('detection_info', {
              'faces_detected': 0,
              'processing_time_ms': stopwatch.elapsedMilliseconds,
              'image_size': image.metadata?.size.toString(),
              'rotation': image.metadata?.rotation.toString(),
              'format': image.metadata?.format.toString(),
              'message': 'Google MLKit não detectou nenhuma face na imagem',
            });
          },
        );
      } else {
        // Log detalhado de cada face detectada
        for (int i = 0; i < faces.length; i++) {
          final face = faces[i];
          debugPrint('[👁️ FaceDetection] Face ${i + 1}:');
          debugPrint('   - BoundingBox: ${face.boundingBox}');
          debugPrint('   - Head Euler Angles: X=${face.headEulerAngleX?.toStringAsFixed(1)}°, '
              'Y=${face.headEulerAngleY?.toStringAsFixed(1)}°, '
              'Z=${face.headEulerAngleZ?.toStringAsFixed(1)}°');
          debugPrint('   - Landmarks: ${face.landmarks.length}');
          debugPrint('   - Tracking ID: ${face.trackingId}');
        }

        await Sentry.captureMessage(
          'Face(s) detectada(s) com sucesso',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setTag('face_detection', 'success');
            scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
            scope.setContexts('detection_info', {
              'faces_detected': faces.length,
              'processing_time_ms': stopwatch.elapsedMilliseconds,
              'image_size': image.metadata?.size.toString(),
              'rotation': image.metadata?.rotation.toString(),
              'format': image.metadata?.format.toString(),
            });
          },
        );
      }

      return faces;
    } catch (e, stackTrace) {
      debugPrint('[❌ FaceDetection] Erro ao detectar faces: $e');
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao detectar faces com Google MLKit',
          'platform': _platformUtils.platformDescription,
        }),
      );
      rethrow;
    }
  }

  /// Detecta rostos em uma imagem de arquivo físico.
  Future<List<Face>> detectFromFile(File file) async {
    try {
      final input = InputImage.fromFile(file);
      return await detect(input);
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao detectar faces a partir de arquivo',
          'file_path': file.path,
        }),
      );
      rethrow;
    }
  }

  /// Detecta rostos a partir de um caminho de arquivo.
  Future<List<Face>> detectFromPath(String path) async {
    try {
      final input = InputImage.fromFilePath(path);
      return await detect(input);
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao detectar faces a partir de caminho',
          'file_path': path,
        }),
      );
      rethrow;
    }
  }

  /// Libera recursos do detector.
  Future<void> dispose() async {
    await _faceDetector?.close();
    _faceDetector = null;
  }
}
