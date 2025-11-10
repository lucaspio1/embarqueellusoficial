import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Utilitário centralizado para gerenciar diferenças de plataforma (iOS/Android)
/// na captura e processamento de imagens da câmera.
///
/// Responsabilidades:
/// - Validar formatos de imagem por plataforma
/// - Fornecer logs detalhados para debug multiplataforma
/// - Identificar plataforma (iOS/Android)
///
/// FASE 3: Lógica de rotação movida para ImageRotationHandler.
/// Este utilitário agora foca em validação e logging.
class PlatformCameraUtils {
  PlatformCameraUtils._();

  static final PlatformCameraUtils instance = PlatformCameraUtils._();

  /// Retorna true se estiver executando no iOS
  bool get isIOS => Platform.isIOS;

  /// Retorna true se estiver executando no Android
  bool get isAndroid => Platform.isAndroid;

  /// Loga informações detalhadas sobre a imagem da câmera para debug
  void logCameraImageInfo(CameraImage image, InputImageRotation rotation) {
    debugPrint('');
    debugPrint('[📸 CameraImage Debug] ==================');
    debugPrint('[📸 CameraImage] Plataforma: ${isIOS ? "iOS" : "Android"}');
    debugPrint('[📸 CameraImage] Dimensões: ${image.width} x ${image.height}');
    debugPrint('[📸 CameraImage] Formato: ${image.format.group} (raw: ${image.format.raw})');
    debugPrint('[📸 CameraImage] Rotação: $rotation');
    debugPrint('[📸 CameraImage] Número de planos: ${image.planes.length}');

    for (int i = 0; i < image.planes.length; i++) {
      final plane = image.planes[i];
      debugPrint('[📸 CameraImage] Plano $i: ${plane.bytes.length} bytes, '
          'bytesPerRow: ${plane.bytesPerRow}, '
          'bytesPerPixel: ${plane.bytesPerPixel}');
    }

    debugPrint('[📸 CameraImage Debug] ==================');
    debugPrint('');
  }

  /// Retorna o formato esperado de imagem para a plataforma atual
  ImageFormatGroup get expectedImageFormat {
    if (isIOS) {
      return ImageFormatGroup.bgra8888;
    } else {
      return ImageFormatGroup.yuv420;
    }
  }

  /// Valida se o formato de imagem está correto para a plataforma
  bool validateImageFormat(ImageFormatGroup format) {
    final expected = expectedImageFormat;
    final isValid = format == expected;

    if (!isValid) {
      debugPrint('[⚠️ PlatformCamera] Formato inesperado!');
      debugPrint('[⚠️ PlatformCamera] Esperado: $expected');
      debugPrint('[⚠️ PlatformCamera] Recebido: $format');

      Sentry.captureMessage(
        '⚠️ FORMAT: Formato de imagem inesperado para plataforma',
        level: SentryLevel.warning,
        withScope: (scope) {
          scope.setTag('platform', isIOS ? 'iOS' : 'Android');
          scope.setContexts('format_validation', {
            'expected_format': expected.toString(),
            'received_format': format.toString(),
            'is_valid': false,
          });
        },
      );
    } else {
      Sentry.captureMessage(
        '✅ FORMAT: Formato de imagem válido',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', isIOS ? 'iOS' : 'Android');
          scope.setContexts('format_validation', {
            'format': format.toString(),
            'is_valid': true,
          });
        },
      );
    }

    return isValid;
  }

  /// Retorna descrição detalhada da plataforma para logs
  String get platformDescription {
    final os = isIOS ? 'iOS' : (isAndroid ? 'Android' : 'Unknown');
    return '$os ${Platform.operatingSystemVersion}';
  }
}
