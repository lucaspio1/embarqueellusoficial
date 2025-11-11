// lib/services/face_detection_service.dart (Substituir o ficheiro)

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

    final minFaceSize = isIOS ? 0.05 : 0.08;
    final performanceMode = FaceDetectorMode.accurate;

    Sentry.captureMessage(
      '🔧 DETECTOR: Criando FaceDetector (FOTOS v2 - Simplificado)',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('platform', isIOS ? 'iOS' : 'Android');
        scope.setTag('detector_mode', 'accurate_simplified'); // ✅ v2
        scope.setTag('min_face_size', minFaceSize.toString());
        scope.setContexts('detector_config', {
          'min_face_size': minFaceSize,
          'performance_mode': 'accurate',
          'enable_landmarks': true,     // ✅ Essencial
          'enable_classification': false, // ✅ Simplificado
          'enable_contours': false,     // ✅ Simplificado
          'purpose': 'photo_processing_not_live',
        });
      },
    );

    // ✅ CONFIGURAÇÃO ATUALIZADA (v2) - MANTÉM PRECISÃO, REMOVE EXTRAS
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: performanceMode,
        enableLandmarks: true,
        enableContours: false,
        enableClassification: false,
        enableTracking: false,
        minFaceSize: minFaceSize,
      ),
    );

    debugPrint('🎯 [FaceDetection] Configurado para FOTOS v2 ${isIOS ? "iOS" : "Android"} '
        '- minFaceSize: $minFaceSize, mode: $performanceMode '
        '- Landmarks: true, Classification: false, Contours: false'); // ✅ v2

    return _faceDetector!;
  }

  /// Detecta rostos em um [InputImage] genérico.
  /// Esta é agora a ÚNICA forma de usar este serviço.
  Future<List<Face>> detect(InputImage input) async {
    final detector = _ensureDetector();
    try {
      final faces = await detector.processImage(input);
      debugPrint('✅ [FaceDetection] Processado. Faces: ${faces.length}');
      return faces;
    } catch (e, stackTrace) {
      debugPrint('❌ [FaceDetection] Erro ao processar imagem: $e');
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'FaceDetectionService.detect()',
          'image_size': '${input.metadata?.size.width}x${input.metadata?.size.height}',
          'image_rotation': input.metadata?.rotation.name,
          'image_format': input.metadata?.format.name,
          'detection_type': 'photo_processing',
        }),
      );
      rethrow;
    }
  }

  // ❌ REMOVIDO: detectFromFile(File file)
  // Esta função usava InputImage.fromFile(), que é a fonte dos problemas no iOS.
  // Ao removê-la, forçamos o FaceImageProcessor a fazer a conversão correta.

  // ❌ REMOVIDO: detectFromPath(String path)
  // Também usava InputImage.fromFilePath(), igualmente problemático.

  void dispose() {
    _faceDetector?.close();
    _faceDetector = null;
    debugPrint('🗑️ [FaceDetection] Detector de fotos liberado.');
  }
}