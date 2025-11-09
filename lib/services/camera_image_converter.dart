import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import 'platform_camera_utils.dart';

/// Conversor centralizado de CameraImage para InputImage.
///
/// Compat\u00edvel com Android (YUV420) e iOS (BGRA8888).
/// Aplica rota\u00e7\u00e3o correta baseada na plataforma e c\u00e2mera.
class CameraImageConverter {
  CameraImageConverter._();

  static final CameraImageConverter instance = CameraImageConverter._();

  final PlatformCameraUtils _platformUtils = PlatformCameraUtils.instance;

  /// Converte [CameraImage] para [InputImage] compat\u00edvel com MLKit.
  ///
  /// [image] - Frame capturado da c\u00e2mera
  /// [camera] - Descri\u00e7\u00e3o da c\u00e2mera (para calcular rota\u00e7\u00e3o)
  /// [enableDebugLogs] - Se true, imprime logs detalhados de debug
  ///
  /// Retorna InputImage configurado corretamente para detec\u00e7\u00e3o facial.
  InputImage convert({
    required CameraImage image,
    required CameraDescription camera,
    bool enableDebugLogs = false,
  }) {
    // Calcular rota\u00e7\u00e3o baseada na plataforma e c\u00e2mera
    final rotation = _platformUtils.getImageRotation(camera: camera);

    if (enableDebugLogs) {
      _platformUtils.logCameraImageInfo(image, rotation);
    }

    // Validar formato de imagem
    final formatGroup = image.format.group;
    _platformUtils.validateImageFormat(formatGroup);

    // Concatenar bytes de todos os planos
    final WriteBuffer buffer = WriteBuffer();
    for (final Plane plane in image.planes) {
      buffer.putUint8List(plane.bytes);
    }
    final Uint8List bytes = buffer.done().buffer.asUint8List();

    // Mapear formato raw para InputImageFormat
    final InputImageFormat? format = _mapInputFormat(image.format.raw);
    if (format == null) {
      throw Exception(
        'Formato de imagem n\u00e3o suportado: ${image.format.group} (raw: ${image.format.raw})',
      );
    }

    // Criar metadata com informa\u00e7\u00f5es corretas
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    if (enableDebugLogs) {
      debugPrint('[\u2705 CameraConverter] InputImage criado com sucesso');
      debugPrint('[\u2705 CameraConverter] Size: ${metadata.size}');
      debugPrint('[\u2705 CameraConverter] Rotation: ${metadata.rotation}');
      debugPrint('[\u2705 CameraConverter] Format: ${metadata.format}');
      debugPrint('[\u2705 CameraConverter] BytesPerRow: ${metadata.bytesPerRow}');
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: metadata,
    );
  }

  /// Mapeia formato raw da c\u00e2mera para InputImageFormat do MLKit.
  ///
  /// Formatos conhecidos:
  /// - 17: NV21 (Android - Samsung)
  /// - 35: YUV_420_888 (Android - padr\u00e3o)
  /// - 842094169: YUV420 (Android)
  /// - 1111970369: BGRA8888 (iOS)
  InputImageFormat? _mapInputFormat(int raw) {
    switch (raw) {
      case 17: // NV21 (Android - Samsung devices)
        debugPrint('[\ud83d\udcf8 Format] NV21 (Android Samsung)');
        return InputImageFormat.nv21;

      case 35: // YUV_420_888 (Android padr\u00e3o)
        debugPrint('[\ud83d\udcf8 Format] YUV_420_888 (Android)');
        return InputImageFormat.yuv_420_888;

      case 842094169: // YUV420 (Android)
        debugPrint('[\ud83d\udcf8 Format] YUV420 (Android)');
        return InputImageFormat.yuv420;

      case 1111970369: // BGRA8888 (iOS)
        debugPrint('[\ud83d\udcf8 Format] BGRA8888 (iOS)');
        return InputImageFormat.bgra8888;

      default:
        debugPrint('[\u26a0\ufe0f Format] Formato desconhecido: $raw');
        // Fallback baseado na plataforma
        if (_platformUtils.isIOS) {
          debugPrint('[\u26a0\ufe0f Format] Assumindo BGRA8888 (iOS)');
          return InputImageFormat.bgra8888;
        } else {
          debugPrint('[\u26a0\ufe0f Format] Assumindo YUV_420_888 (Android)');
          return InputImageFormat.yuv_420_888;
        }
    }
  }
}
