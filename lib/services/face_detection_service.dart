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
      Sentry.captureMessage(
        '✅ DETECTOR: Reutilizando detector existente',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
        },
      );
      return _faceDetector!;
    }

    Sentry.captureMessage(
      '🔧 DETECTOR: Criando novo FaceDetector do Google MLKit',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
        scope.setContexts('detector_config', {
          'performance_mode': 'accurate',
          'contours_enabled': false,
          'landmarks_enabled': false,
          'classification_enabled': false,
          'min_face_size': 0.1,
        });
      },
    );

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableContours: false,
        enableLandmarks: false,
        enableClassification: false,
        minFaceSize: 0.1,
      ),
    );

    Sentry.captureMessage(
      '✅ DETECTOR: FaceDetector criado com sucesso',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
      },
    );

    return _faceDetector!;
  }

  /// Detecta rostos em uma [InputImage].
  Future<List<Face>> detect(InputImage image) async {
    try {
      await Sentry.captureMessage(
        '🔍 DETECTION: Iniciando detecção de faces com Google MLKit',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
          scope.setContexts('detection_start', {
            'image_width': image.metadata?.size.width.toInt(),
            'image_height': image.metadata?.size.height.toInt(),
            'image_rotation': image.metadata?.rotation.toString(),
            'image_format': image.metadata?.format.toString(),
            'bytes_per_row': image.metadata?.bytesPerRow,
          });
        },
      );

      final detector = _ensureDetector();
      final stopwatch = Stopwatch()..start();

      final faces = await detector.processImage(image);

      stopwatch.stop();

      if (faces.isEmpty) {
        await Sentry.captureMessage(
          '❌ DETECTION: NENHUMA FACE DETECTADA',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('face_detection', 'no_faces_found');
            scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
            scope.setContexts('detection_failed', {
              'faces_detected': 0,
              'processing_time_ms': stopwatch.elapsedMilliseconds,
              'image_width': image.metadata?.size.width.toInt(),
              'image_height': image.metadata?.size.height.toInt(),
              'image_rotation': image.metadata?.rotation.toString(),
              'image_format': image.metadata?.format.toString(),
              'bytes_per_row': image.metadata?.bytesPerRow,
              'message': 'Google MLKit não detectou nenhuma face na imagem',
              'possible_causes': 'Imagem muito escura, face muito pequena, rotação incorreta, ou formato inválido',
            });
          },
        );
      } else {
        // Coletar informações detalhadas de todas as faces detectadas
        final facesInfo = faces.map((face) {
          return {
            'bounding_box': '${face.boundingBox.width.toInt()}x${face.boundingBox.height.toInt()}',
            'bounding_box_position': '(${face.boundingBox.left.toInt()}, ${face.boundingBox.top.toInt()})',
            'head_euler_x': face.headEulerAngleX?.toStringAsFixed(2),
            'head_euler_y': face.headEulerAngleY?.toStringAsFixed(2),
            'head_euler_z': face.headEulerAngleZ?.toStringAsFixed(2),
            'left_eye_open_prob': face.leftEyeOpenProbability?.toStringAsFixed(2),
            'right_eye_open_prob': face.rightEyeOpenProbability?.toStringAsFixed(2),
            'smiling_prob': face.smilingProbability?.toStringAsFixed(2),
            'tracking_id': face.trackingId,
            'landmarks_count': face.landmarks.length,
          };
        }).toList();

        await Sentry.captureMessage(
          '✅ DETECTION: Face(s) detectada(s) com SUCESSO',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setTag('face_detection', 'success');
            scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
            scope.setContexts('detection_success', {
              'faces_detected': faces.length,
              'processing_time_ms': stopwatch.elapsedMilliseconds,
              'image_width': image.metadata?.size.width.toInt(),
              'image_height': image.metadata?.size.height.toInt(),
              'image_rotation': image.metadata?.rotation.toString(),
              'image_format': image.metadata?.format.toString(),
              'faces_details': facesInfo.toString(),
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
          'context': 'Erro CRÍTICO ao detectar faces com Google MLKit',
          'platform': _platformUtils.platformDescription,
          'image_width': image.metadata?.size.width.toInt(),
          'image_height': image.metadata?.size.height.toInt(),
          'image_rotation': image.metadata?.rotation.toString(),
          'image_format': image.metadata?.format.toString(),
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
