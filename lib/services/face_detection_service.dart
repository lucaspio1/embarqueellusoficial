import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'platform_camera_utils.dart';

/// Singleton responsável por detectar rostos utilizando o Google MLKit.
///
/// OTIMIZADO PARA DETECÇÃO EM FOTOS (não ao vivo) - máxima precisão.
/// Configuração adaptativa por plataforma (iOS mais sensível que Android).
class FaceDetectionService {
  FaceDetectionService._();

  static final FaceDetectionService instance = FaceDetectionService._();

  FaceDetector? _faceDetector;
  final PlatformCameraUtils _platformUtils = PlatformCameraUtils.instance;

  FaceDetector _ensureDetector() {
    if (_faceDetector != null) {
      return _faceDetector!;
    }

    // ✅ CONFIGURAÇÃO MAXIMIZADA PARA FOTOS (NÃO AO VIVO)
    final bool isIOS = _platformUtils.isIOS;

    // FOTOS: Podemos ser MUITO mais sensíveis - não precisa de performance em tempo real
    final minFaceSize = isIOS ? 0.05 : 0.08; // iOS 5%, Android 8% - MUITO SENSÍVEL
    final performanceMode = FaceDetectorMode.accurate; // SEMPRE ACCURATE para fotos

    Sentry.captureMessage(
      '🔧 DETECTOR: Criando FaceDetector PARA FOTOS | ${isIOS ? "iOS" : "Android"}',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('platform', isIOS ? 'iOS' : 'Android');
        scope.setTag('detector_mode', 'accurate_max_precision');
        scope.setTag('min_face_size', minFaceSize.toString());
        scope.setContexts('detector_config', {
          'min_face_size': minFaceSize,
          'performance_mode': 'accurate',
          'enable_landmarks': true,
          'enable_classification': true,
          'enable_contours': true,
          'purpose': 'photo_processing_not_live',
        });
      },
    );

    // ✅ CONFIGURAÇÃO MAXIMIZADA - FOTOS PODEM TER MÁXIMA PRECISÃO
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: performanceMode,
        enableContours: true,      // ✅ FOTOS: Podemos habilitar
        enableLandmarks: true,     // ✅ FOTOS: Landmarks úteis para alinhamento
        enableClassification: true, // ✅ FOTOS: Classificação útil (olhos abertos, etc)
        enableTracking: false,     // ❌ Não precisa de tracking (não é vídeo)
        minFaceSize: minFaceSize,  // ✅ MUITO sensível
      ),
    );

    debugPrint('🎯 [FaceDetection] Configurado para FOTOS ${isIOS ? "iOS" : "Android"} '
          '- minFaceSize: $minFaceSize, mode: $performanceMode '
          '- Landmarks: true, Classification: true');

    return _faceDetector!;
  }

  /// Detecta rostos em uma [InputImage] - MÁXIMA PRECISÃO PARA FOTOS
  Future<List<Face>> detect(InputImage image) async {
    try {
      final detector = _ensureDetector();
      final stopwatch = Stopwatch()..start();
      final bool isIOS = _platformUtils.isIOS;

      Sentry.captureMessage(
        '🔍 DETECTION PHOTO: ${image.metadata?.size.width}x${image.metadata?.size.height}',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', isIOS ? 'iOS' : 'Android');
          scope.setTag('detection_type', 'photo_processing');
          scope.setTag('image_width', '${image.metadata?.size.width}');
          scope.setTag('image_height', '${image.metadata?.size.height}');
          scope.setTag('rotation', '${image.metadata?.rotation}');
          scope.setTag('format', '${image.metadata?.format}');
        },
      );

      // ✅ FOTOS: SEM timeout - podemos esperar o tempo que for necessário
      final List<Face> faces = await detector.processImage(image);

      stopwatch.stop();

      if (faces.isEmpty) {
        Sentry.captureMessage(
          '❌ NENHUMA FACE DETECTADA NA FOTO | ${stopwatch.elapsedMilliseconds}ms',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('platform', isIOS ? 'iOS' : 'Android');
            scope.setTag('detection_result', 'no_faces_in_photo');
            scope.setTag('processing_time_ms', '${stopwatch.elapsedMilliseconds}');
            scope.setTag('image_size', '${image.metadata?.size.width}x${image.metadata?.size.height}');
            scope.setContexts('photo_detection_failure', {
              'min_face_size_required': '${isIOS ? "5%" : "8%"}',
              'processing_time': '${stopwatch.elapsedMilliseconds}ms',
              'possible_causes': [
                'Face muito pequena (< ${isIOS ? "5%" : "8%"})',
                'Problema de orientação EXIF (iOS)',
                'Iluminação inadequada',
                'Rosto muito inclinado ou ocluído',
                'Qualidade da imagem muito baixa'
              ],
            });
          },
        );
      } else {
        final face = faces.first;

        // Calcular percentual da face em relação à imagem (com null safety)
        String facePercent = 'unknown';
        if (image.metadata?.size != null) {
          final imageArea = image.metadata!.size.width * image.metadata!.size.height;
          final faceArea = face.boundingBox.width * face.boundingBox.height;
          facePercent = ((faceArea / imageArea) * 100).toStringAsFixed(1);
        }

        // ✅ INFORMAÇÕES DETALHADAS PARA FOTOS
        final leftEyeOpen = face.leftEyeOpenProbability;
        final rightEyeOpen = face.rightEyeOpenProbability;
        final smiling = face.smilingProbability;

        Sentry.captureMessage(
          '✅ ${faces.length} FACE(S) DETECTADA(S) NA FOTO | ${stopwatch.elapsedMilliseconds}ms',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setTag('platform', isIOS ? 'iOS' : 'Android');
            scope.setTag('faces_count', '${faces.length}');
            scope.setTag('processing_time_ms', '${stopwatch.elapsedMilliseconds}');
            scope.setTag('face_size_percent', facePercent);
            scope.setContexts('photo_detection_success', {
              'bbox_width': face.boundingBox.width.toInt(),
              'bbox_height': face.boundingBox.height.toInt(),
              'bbox_left': face.boundingBox.left.toInt(),
              'bbox_top': face.boundingBox.top.toInt(),
              'face_percent_of_image': '$facePercent%',
              'min_required_percent': isIOS ? '5%' : '8%',
              'detection_time_ms': stopwatch.elapsedMilliseconds,
              'left_eye_open_prob': leftEyeOpen,
              'right_eye_open_prob': rightEyeOpen,
              'smiling_prob': smiling,
              'landmarks_count': face.landmarks.length,
              'metadata_available': image.metadata != null,
            });
          },
        );

        // ✅ LOG DETALHADO PARA DEBUG
        debugPrint('📸 [${isIOS ? "iOS" : "Android"}] Face detectada na FOTO: '
              '${face.boundingBox.width.toInt()}x${face.boundingBox.height.toInt()} '
              '($facePercent% da imagem) '
              'em ${stopwatch.elapsedMilliseconds}ms '
              'Olhos: L${leftEyeOpen?.toStringAsFixed(2) ?? "N/A"}/'
              'R${rightEyeOpen?.toStringAsFixed(2) ?? "N/A"}');
      }

      return faces;
    } catch (e, stackTrace) {
      final bool isIOS = _platformUtils.isIOS;
      debugPrint('❌ [${isIOS ? "iOS" : "Android"}] Erro na detecção de FOTO: $e');

      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'ERRO na detecção facial em FOTO - ${isIOS ? "iOS" : "Android"}',
          'platform': _platformUtils.platformDescription,
          'detection_type': 'photo_processing',
        }),
      );

      rethrow;
    }
  }

  /// Detecta rostos em uma imagem de arquivo físico - MÁXIMA PRECISÃO
  Future<List<Face>> detectFromFile(File file) async {
    try {
      final bool isIOS = _platformUtils.isIOS;

      // ✅ LOG DETALHADO PARA FOTOS
      final fileSize = await file.length();
      final fileStat = await file.stat();
      final modified = fileStat.modified;

      debugPrint('📸 [${isIOS ? "iOS" : "Android"}] Detectando faces em FOTO: '
            '${file.path} '
            '(${(fileSize / 1024).toStringAsFixed(1)} KB) '
            'Modificado: $modified');

      final input = InputImage.fromFile(file);
      return await detect(input);
    } catch (e, stackTrace) {
      final bool isIOS = _platformUtils.isIOS;
      debugPrint('❌ [${isIOS ? "iOS" : "Android"}] Erro detectFromFile (FOTO): $e');

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
    debugPrint('🔌 FaceDetectionService disposed');
  }
}
