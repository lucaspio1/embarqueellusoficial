import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Resultado da detecção e recorte facial nativo.
class NativeFaceResult {
  /// Bytes da face recortada (JPEG, 112x112) - pronta para embeddings
  final Uint8List croppedFaceBytes;

  /// Coordenadas da bounding box da face detectada
  final Rect boundingBox;

  const NativeFaceResult({
    required this.croppedFaceBytes,
    required this.boundingBox,
  });

  @override
  String toString() {
    return 'NativeFaceResult('
        'croppedFaceBytes: ${croppedFaceBytes.length} bytes, '
        'boundingBox: ${boundingBox.width.toInt()}x${boundingBox.height.toInt()}'
        ')';
  }
}

/// Serviço para processar detecção facial nativamente (iOS/Android).
///
/// PROPÓSITO: Resolver o bug do InputImage.fromFile() no iOS que ignora
/// metadados EXIF de rotação.
///
/// FUNCIONAMENTO:
/// 1. Flutter (Dart) envia imagePath via Platform Channel
/// 2. Nativo (Swift/Kotlin) carrega imagem respeitando EXIF
/// 3. Nativo detecta face usando ML Kit nativo
/// 4. Nativo recorta e redimensiona para 112x112
/// 5. Retorna bytes JPEG da face para Flutter
///
/// RESPONSABILIDADES NATIVAS:
/// - Correção automática de EXIF (UIImage no iOS, ExifInterface no Android)
/// - Detecção facial com SDK nativo do ML Kit
/// - Recorte e redimensionamento da face
/// - Conversão para JPEG
class NativeFaceService {
  NativeFaceService._();

  static final NativeFaceService instance = NativeFaceService._();

  /// Nome do Platform Channel
  static const String _channelName = 'embarqueellus/native_face_detection';

  /// Method Channel para comunicação com código nativo
  final MethodChannel _channel = const MethodChannel(_channelName);

  /// Detecta e recorta face usando processamento nativo.
  ///
  /// [imagePath] - Caminho da imagem capturada
  ///
  /// Retorna [NativeFaceResult] contendo:
  /// - croppedFaceBytes: Uint8List da face recortada (pronta para embeddings)
  /// - boundingBox: Coordenadas da face detectada
  ///
  /// Lança exceção se:
  /// - Nenhuma face foi detectada
  /// - Erro no processamento nativo
  Future<NativeFaceResult> detectAndCropFace(String imagePath) async {
    try {
      await Sentry.captureMessage(
        '🔧 NATIVE_FACE: Iniciando detecção nativa',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('native_detection_start', {
            'image_path': imagePath,
            'channel': _channelName,
          });
        },
      );

      // Chamar o método nativo
      final Map<dynamic, dynamic> result = await _channel.invokeMethod(
        'detectAndCropFace',
        {'path': imagePath},
      );

      // Extrair bytes da face recortada
      final Uint8List croppedFaceBytes = result['croppedFaceBytes'] as Uint8List;

      // Extrair boundingBox
      final Map<dynamic, dynamic> bbox = result['boundingBox'] as Map<dynamic, dynamic>;
      final Rect boundingBox = Rect.fromLTWH(
        (bbox['left'] as num).toDouble(),
        (bbox['top'] as num).toDouble(),
        (bbox['width'] as num).toDouble(),
        (bbox['height'] as num).toDouble(),
      );

      await Sentry.captureMessage(
        '✅ NATIVE_FACE: Detecção nativa concluída',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('native_detection_complete', {
            'cropped_bytes_size': croppedFaceBytes.length,
            'bbox_width': boundingBox.width.toInt(),
            'bbox_height': boundingBox.height.toInt(),
          });
        },
      );

      return NativeFaceResult(
        croppedFaceBytes: croppedFaceBytes,
        boundingBox: boundingBox,
      );
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro na detecção facial nativa',
          'image_path': imagePath,
          'channel': _channelName,
        }),
      );
      rethrow;
    }
  }
}
