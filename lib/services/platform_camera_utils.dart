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
/// - Calcular rotação correta do InputImage baseado na plataforma
/// - Corrigir diferenças de sensorOrientation entre iOS e Android
/// - Fornecer logs detalhados para debug multiplataforma
class PlatformCameraUtils {
  PlatformCameraUtils._();

  static final PlatformCameraUtils instance = PlatformCameraUtils._();

  /// Retorna true se estiver executando no iOS
  bool get isIOS => Platform.isIOS;

  /// Retorna true se estiver executando no Android
  bool get isAndroid => Platform.isAndroid;

  /// Calcula a rotação correta do InputImage baseado na câmera e orientação do device.
  ///
  /// Para câmera traseira:
  /// - Android: geralmente rotation0deg (landscape) ou rotation90deg (portrait)
  /// - iOS: pode variar, precisa ajuste baseado em sensorOrientation
  ///
  /// [camera] - Descrição da câmera (lensDirection, sensorOrientation)
  /// [deviceOrientation] - Orientação atual do dispositivo
  InputImageRotation getImageRotation({
    required CameraDescription camera,
    DeviceOrientation? deviceOrientation,
  }) {
    // Orientação padrão: portrait up
    final orientation = deviceOrientation ?? DeviceOrientation.portraitUp;

    // Sensor orientation da câmera (graus: 0, 90, 180, 270)
    final int sensorOrientation = camera.sensorOrientation;

    // Log de debug
    debugPrint('[📱 PlatformCamera] Plataforma: ${isIOS ? "iOS" : "Android"}');
    debugPrint('[📱 PlatformCamera] Câmera: ${camera.lensDirection}');
    debugPrint('[📱 PlatformCamera] Sensor Orientation: $sensorOrientation°');
    debugPrint('[📱 PlatformCamera] Device Orientation: $orientation');

    Sentry.captureMessage(
      '🔄 ROTATION: Calculando rotação da imagem',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('platform', isIOS ? 'iOS' : 'Android');
        scope.setContexts('rotation_calc', {
          'camera_name': camera.name,
          'camera_direction': camera.lensDirection.toString(),
          'sensor_orientation': '$sensorOrientation°',
          'device_orientation': orientation.toString(),
          'is_back_camera': camera.lensDirection == CameraLensDirection.back,
        });
      },
    );

    InputImageRotation rotation;

    if (isIOS) {
      // iOS: comportamento específico
      // Para câmera traseira, iOS geralmente retorna sensorOrientation = 90
      // Para câmera frontal, geralmente = 270
      rotation = _getRotationForIOS(
        sensorOrientation: sensorOrientation,
        deviceOrientation: orientation,
        isBackCamera: camera.lensDirection == CameraLensDirection.back,
      );
    } else {
      // Android: comportamento padrão
      rotation = _getRotationForAndroid(
        sensorOrientation: sensorOrientation,
        deviceOrientation: orientation,
      );
    }

    Sentry.captureMessage(
      '✅ ROTATION: Rotação calculada',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('platform', isIOS ? 'iOS' : 'Android');
        scope.setContexts('rotation_result', {
          'rotation': rotation.toString(),
          'rotation_degrees': _rotationToDegrees(rotation),
          'sensor_orientation': '$sensorOrientation°',
          'camera_direction': camera.lensDirection.toString(),
        });
      },
    );

    debugPrint('[📱 PlatformCamera] Rotação InputImage: $rotation');
    return rotation;
  }

  int _rotationToDegrees(InputImageRotation rotation) {
    switch (rotation) {
      case InputImageRotation.rotation0deg:
        return 0;
      case InputImageRotation.rotation90deg:
        return 90;
      case InputImageRotation.rotation180deg:
        return 180;
      case InputImageRotation.rotation270deg:
        return 270;
    }
  }

  /// Cálculo de rotação para iOS
  InputImageRotation _getRotationForIOS({
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
    required bool isBackCamera,
  }) {
    Sentry.captureMessage(
      '📱 iOS ROTATION: Calculando rotação específica para iOS',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('platform', 'iOS');
        scope.setContexts('ios_rotation_input', {
          'sensor_orientation': '$sensorOrientation°',
          'device_orientation': deviceOrientation.toString(),
          'is_back_camera': isBackCamera,
        });
      },
    );

    InputImageRotation result;

    // iOS: ajuste específico para câmera traseira
    // Em portrait mode, câmera traseira geralmente precisa rotation90deg
    if (isBackCamera) {
      switch (deviceOrientation) {
        case DeviceOrientation.portraitUp:
          result = InputImageRotation.rotation90deg;
          break;
        case DeviceOrientation.portraitDown:
          result = InputImageRotation.rotation270deg;
          break;
        case DeviceOrientation.landscapeLeft:
          result = InputImageRotation.rotation180deg;
          break;
        case DeviceOrientation.landscapeRight:
          result = InputImageRotation.rotation0deg;
          break;
      }

      Sentry.captureMessage(
        '✅ iOS ROTATION: Rotação da câmera traseira calculada',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', 'iOS');
          scope.setTag('camera_type', 'back');
          scope.setContexts('ios_back_rotation', {
            'device_orientation': deviceOrientation.toString(),
            'rotation_applied': result.toString(),
            'rotation_degrees': _rotationToDegrees(result),
          });
        },
      );

      return result;
    }

    // Câmera frontal iOS
    result = _rotationFromSensorOrientation(sensorOrientation);

    Sentry.captureMessage(
      '✅ iOS ROTATION: Rotação da câmera frontal calculada',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('platform', 'iOS');
        scope.setTag('camera_type', 'front');
        scope.setContexts('ios_front_rotation', {
          'sensor_orientation': '$sensorOrientation°',
          'rotation_applied': result.toString(),
          'rotation_degrees': _rotationToDegrees(result),
        });
      },
    );

    return result;
  }

  /// Cálculo de rotação para Android
  InputImageRotation _getRotationForAndroid({
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
  }) {
    // Android: usa sensorOrientation diretamente na maioria dos casos
    // Para portrait mode, a rotação é geralmente baseada no sensor
    return _rotationFromSensorOrientation(sensorOrientation);
  }

  /// Converte sensorOrientation (graus) para InputImageRotation
  InputImageRotation _rotationFromSensorOrientation(int sensorOrientation) {
    switch (sensorOrientation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        // Fallback para rotação padrão (portrait)
        debugPrint('[⚠️ PlatformCamera] SensorOrientation inválido: $sensorOrientation°, usando 90°');
        return InputImageRotation.rotation90deg;
    }
  }

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
