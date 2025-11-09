import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'platform_camera_utils.dart';

/// Conversor centralizado de CameraImage para InputImage.
///
/// Compatível com Android (YUV420) e iOS (BGRA8888).
/// Aplica rotação correta baseada na plataforma e câmera.
class CameraImageConverter {
  CameraImageConverter._();

  static final CameraImageConverter instance = CameraImageConverter._();

  final PlatformCameraUtils _platformUtils = PlatformCameraUtils.instance;

  /// Converte [CameraImage] para [InputImage] compatível com MLKit.
  ///
  /// [image] - Frame capturado da câmera
  /// [camera] - Descrição da câmera (para calcular rotação)
  /// [enableDebugLogs] - Se true, imprime logs detalhados de debug
  ///
  /// Retorna InputImage configurado corretamente para detecção facial.
  InputImage convert({
    required CameraImage image,
    required CameraDescription camera,
    bool enableDebugLogs = false,
  }) {
    // Log inicial da conversão
    Sentry.captureMessage(
      '🔄 CONVERTER: Iniciando conversão de CameraImage para InputImage',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
        scope.setContexts('image_input', {
          'width': image.width,
          'height': image.height,
          'format_group': image.format.group.toString(),
          'format_raw': image.format.raw,
          'planes_count': image.planes.length,
          'camera_name': camera.name,
          'camera_direction': camera.lensDirection.toString(),
          'sensor_orientation': '${camera.sensorOrientation}°',
        });
      },
    );

    // Calcular rotação baseada na plataforma e câmera
    final rotation = _platformUtils.getImageRotation(camera: camera);

    if (enableDebugLogs) {
      _platformUtils.logCameraImageInfo(image, rotation);
    }

    // Validar formato de imagem
    final formatGroup = image.format.group;
    final isFormatValid = _platformUtils.validateImageFormat(formatGroup);

    if (!isFormatValid) {
      Sentry.captureMessage(
        '⚠️ CONVERTER: Formato de imagem inesperado para a plataforma',
        level: SentryLevel.warning,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
          scope.setContexts('format_warning', {
            'format_group': formatGroup.toString(),
            'format_raw': image.format.raw,
            'expected_format': _platformUtils.expectedImageFormat.toString(),
          });
        },
      );
    }

    // Concatenar bytes de todos os planos
    final WriteBuffer buffer = WriteBuffer();
    for (final Plane plane in image.planes) {
      buffer.putUint8List(plane.bytes);
    }
    final Uint8List bytes = buffer.done().buffer.asUint8List();

    Sentry.captureMessage(
      '📊 CONVERTER: Bytes concatenados de todos os planos',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setContexts('bytes_info', {
          'total_bytes': bytes.length,
          'planes_processed': image.planes.length,
        });
      },
    );

    // Mapear formato raw para InputImageFormat
    final InputImageFormat? format = _mapInputFormat(image.format.raw);
    if (format == null) {
      Sentry.captureException(
        Exception('Formato de imagem não suportado'),
        hint: Hint.withMap({
          'context': 'Erro ao mapear formato de imagem',
          'format_group': image.format.group.toString(),
          'format_raw': image.format.raw,
          'platform': _platformUtils.platformDescription,
        }),
      );
      throw Exception(
        'Formato de imagem não suportado: ${image.format.group} (raw: ${image.format.raw})',
      );
    }

    // Criar metadata com informações corretas
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    Sentry.captureMessage(
      '✅ CONVERTER: InputImage criado com sucesso',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
        scope.setContexts('inputimage_created', {
          'size': '${metadata.size.width.toInt()}x${metadata.size.height.toInt()}',
          'rotation': metadata.rotation.toString(),
          'format': metadata.format.toString(),
          'bytes_per_row': metadata.bytesPerRow,
          'total_bytes': bytes.length,
        });
      },
    );

    if (enableDebugLogs) {
      debugPrint('[✅ CameraConverter] InputImage criado com sucesso');
      debugPrint('[✅ CameraConverter] Size: ${metadata.size}');
      debugPrint('[✅ CameraConverter] Rotation: ${metadata.rotation}');
      debugPrint('[✅ CameraConverter] Format: ${metadata.format}');
      debugPrint('[✅ CameraConverter] BytesPerRow: ${metadata.bytesPerRow}');
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: metadata,
    );
  }

  /// Mapeia formato raw da câmera para InputImageFormat do MLKit.
  ///
  /// Formatos conhecidos:
  /// - 17: NV21 (Android - Samsung)
  /// - 35: YUV_420_888 (Android - padrão)
  /// - 842094169: YUV420 (Android)
  /// - 1111970369: BGRA8888 (iOS)
  InputImageFormat? _mapInputFormat(int raw) {
    switch (raw) {
      case 17: // NV21 (Android - Samsung devices)
        Sentry.captureMessage(
          '📸 FORMAT: NV21 (Android Samsung)',
          level: SentryLevel.info,
        );
        debugPrint('[📸 Format] NV21 (Android Samsung)');
        return InputImageFormat.nv21;

      case 35: // YUV_420_888 (Android padrão)
        Sentry.captureMessage(
          '📸 FORMAT: YUV_420_888 (Android)',
          level: SentryLevel.info,
        );
        debugPrint('[📸 Format] YUV_420_888 (Android)');
        return InputImageFormat.yuv_420_888;

      case 842094169: // YUV420 (Android)
        Sentry.captureMessage(
          '📸 FORMAT: YUV420 (Android)',
          level: SentryLevel.info,
        );
        debugPrint('[📸 Format] YUV420 (Android)');
        return InputImageFormat.yuv420;

      case 1111970369: // BGRA8888 (iOS)
        Sentry.captureMessage(
          '📸 FORMAT: BGRA8888 (iOS)',
          level: SentryLevel.info,
        );
        debugPrint('[📸 Format] BGRA8888 (iOS)');
        return InputImageFormat.bgra8888;

      default:
        Sentry.captureMessage(
          '⚠️ FORMAT: Formato desconhecido - usando fallback',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
            scope.setContexts('format_unknown', {
              'format_raw': raw,
              'fallback_to': _platformUtils.isIOS ? 'BGRA8888' : 'YUV_420_888',
            });
          },
        );
        debugPrint('[⚠️ Format] Formato desconhecido: $raw');
        // Fallback baseado na plataforma
        if (_platformUtils.isIOS) {
          debugPrint('[⚠️ Format] Assumindo BGRA8888 (iOS)');
          return InputImageFormat.bgra8888;
        } else {
          debugPrint('[⚠️ Format] Assumindo YUV_420_888 (Android)');
          return InputImageFormat.yuv_420_888;
        }
    }
  }
}
