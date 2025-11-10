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
    if (_faceDetector != null) {
      return _faceDetector!;
    }

    Sentry.captureMessage(
      '🔧 DETECTOR: Criando FaceDetector | mode=FAST | minSize=5% | tracking=ON',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
        scope.setTag('detector_mode', 'fast');
        scope.setTag('min_face_size', '0.05');
      },
    );

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableContours: false,
        enableLandmarks: false,
        enableClassification: false,
        enableTracking: true,
        minFaceSize: 0.05,
      ),
    );

    return _faceDetector!;
  }

  /// Detecta rostos em uma [InputImage].
  Future<List<Face>> detect(InputImage image) async {
    try {
      final detector = _ensureDetector();
      final stopwatch = Stopwatch()..start();

      Sentry.captureMessage(
        '🔍 DETECTION START: ${image.metadata?.size.width}x${image.metadata?.size.height}',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('image_width', '${image.metadata?.size.width}');
          scope.setTag('image_height', '${image.metadata?.size.height}');
          scope.setTag('rotation', '${image.metadata?.rotation}');
          scope.setTag('format', '${image.metadata?.format}');
        },
      );

      final faces = await detector.processImage(image);

      stopwatch.stop();

      if (faces.isEmpty) {
        Sentry.captureMessage(
          '❌ NENHUMA FACE DETECTADA | ${stopwatch.elapsedMilliseconds}ms',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('detection_result', 'no_faces');
            scope.setTag('processing_time_ms', '${stopwatch.elapsedMilliseconds}');
            scope.setTag('image_size', '${image.metadata?.size.width}x${image.metadata?.size.height}');
            scope.setContexts('possible_causes', {
              'cause_1': 'Imagem muito escura ou clara',
              'cause_2': 'Face < 5% da imagem',
              'cause_3': 'Rotação incorreta',
              'cause_4': 'Face coberta ou ângulo ruim',
            });
          },
        );
      } else {
        final face = faces.first;
        final facePercent = ((face.boundingBox.width * face.boundingBox.height) /
                            (image.metadata!.size.width * image.metadata!.size.height) * 100).toStringAsFixed(1);

        Sentry.captureMessage(
          '✅ ${faces.length} FACE(S) DETECTADA(S) | ${stopwatch.elapsedMilliseconds}ms',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setTag('faces_count', '${faces.length}');
            scope.setTag('processing_time_ms', '${stopwatch.elapsedMilliseconds}');
            scope.setTag('face_size_percent', facePercent);
            scope.setContexts('primary_face', {
              'bbox_width': face.boundingBox.width.toInt(),
              'bbox_height': face.boundingBox.height.toInt(),
              'bbox_left': face.boundingBox.left.toInt(),
              'bbox_top': face.boundingBox.top.toInt(),
              'face_percent_of_image': '$facePercent%',
            });
          },
        );
      }

      return faces;
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'ERRO CRÍTICO ao detectar faces',
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
      await Sentry.captureException(e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Detecta rostos a partir de um caminho de arquivo.
  Future<List<Face>> detectFromPath(String path) async {
    try {
      final input = InputImage.fromFilePath(path);
      return await detect(input);
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Libera recursos do detector.
  Future<void> dispose() async {
    await _faceDetector?.close();
    _faceDetector = null;
  }
}
