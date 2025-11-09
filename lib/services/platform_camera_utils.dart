import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Utilit\u00e1rio centralizado para gerenciar diferen\u00e7as de plataforma (iOS/Android)
/// na captura e processamento de imagens da c\u00e2mera.
///
/// Responsabilidades:
/// - Calcular rota\u00e7\u00e3o correta do InputImage baseado na plataforma
/// - Corrigir diferen\u00e7as de sensorOrientation entre iOS e Android
/// - Fornecer logs detalhados para debug multiplataforma
class PlatformCameraUtils {
  PlatformCameraUtils._();

  static final PlatformCameraUtils instance = PlatformCameraUtils._();

  /// Retorna true se estiver executando no iOS
  bool get isIOS => Platform.isIOS;

  /// Retorna true se estiver executando no Android
  bool get isAndroid => Platform.isAndroid;

  /// Calcula a rota\u00e7\u00e3o correta do InputImage baseado na c\u00e2mera e orienta\u00e7\u00e3o do device.
  ///
  /// Para c\u00e2mera traseira:
  /// - Android: geralmente rotation0deg (landscape) ou rotation90deg (portrait)
  /// - iOS: pode variar, precisa ajuste baseado em sensorOrientation
  ///
  /// [camera] - Descri\u00e7\u00e3o da c\u00e2mera (lensDirection, sensorOrientation)
  /// [deviceOrientation] - Orienta\u00e7\u00e3o atual do dispositivo
  InputImageRotation getImageRotation({
    required CameraDescription camera,
    DeviceOrientation? deviceOrientation,
  }) {
    // Orienta\u00e7\u00e3o padr\u00e3o: portrait up
    final orientation = deviceOrientation ?? DeviceOrientation.portraitUp;

    // Sensor orientation da c\u00e2mera (graus: 0, 90, 180, 270)
    final int sensorOrientation = camera.sensorOrientation;

    // Log de debug
    debugPrint('[\ud83d\udcf1 PlatformCamera] Plataforma: ${isIOS ? "iOS" : "Android"}');
    debugPrint('[\ud83d\udcf1 PlatformCamera] C\u00e2mera: ${camera.lensDirection}');
    debugPrint('[\ud83d\udcf1 PlatformCamera] Sensor Orientation: $sensorOrientation\u00b0');
    debugPrint('[\ud83d\udcf1 PlatformCamera] Device Orientation: $orientation');

    InputImageRotation rotation;

    if (isIOS) {
      // iOS: comportamento espec\u00edfico
      // Para c\u00e2mera traseira, iOS geralmente retorna sensorOrientation = 90
      // Para c\u00e2mera frontal, geralmente = 270
      rotation = _getRotationForIOS(
        sensorOrientation: sensorOrientation,
        deviceOrientation: orientation,
        isBackCamera: camera.lensDirection == CameraLensDirection.back,
      );
    } else {
      // Android: comportamento padr\u00e3o
      rotation = _getRotationForAndroid(
        sensorOrientation: sensorOrientation,
        deviceOrientation: orientation,
      );
    }

    debugPrint('[\ud83d\udcf1 PlatformCamera] Rota\u00e7\u00e3o InputImage: $rotation');
    return rotation;
  }

  /// C\u00e1lculo de rota\u00e7\u00e3o para iOS
  InputImageRotation _getRotationForIOS({
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
    required bool isBackCamera,
  }) {
    // iOS: ajuste espec\u00edfico para c\u00e2mera traseira
    // Em portrait mode, c\u00e2mera traseira geralmente precisa rotation90deg
    if (isBackCamera) {
      switch (deviceOrientation) {
        case DeviceOrientation.portraitUp:
          return InputImageRotation.rotation90deg;
        case DeviceOrientation.portraitDown:
          return InputImageRotation.rotation270deg;
        case DeviceOrientation.landscapeLeft:
          return InputImageRotation.rotation180deg;
        case DeviceOrientation.landscapeRight:
          return InputImageRotation.rotation0deg;
      }
    }

    // C\u00e2mera frontal iOS
    return _rotationFromSensorOrientation(sensorOrientation);
  }

  /// C\u00e1lculo de rota\u00e7\u00e3o para Android
  InputImageRotation _getRotationForAndroid({
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
  }) {
    // Android: usa sensorOrientation diretamente na maioria dos casos
    // Para portrait mode, a rota\u00e7\u00e3o \u00e9 geralmente baseada no sensor
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
        // Fallback para rota\u00e7\u00e3o padr\u00e3o (portrait)
        debugPrint('[\u26a0\ufe0f PlatformCamera] SensorOrientation inv\u00e1lido: $sensorOrientation\u00b0, usando 90\u00b0');
        return InputImageRotation.rotation90deg;
    }
  }

  /// Loga informa\u00e7\u00f5es detalhadas sobre a imagem da c\u00e2mera para debug
  void logCameraImageInfo(CameraImage image, InputImageRotation rotation) {
    debugPrint('');
    debugPrint('[\ud83d\udcf8 CameraImage Debug] ==================');
    debugPrint('[\ud83d\udcf8 CameraImage] Plataforma: ${isIOS ? "iOS" : "Android"}');
    debugPrint('[\ud83d\udcf8 CameraImage] Dimens\u00f5es: ${image.width} x ${image.height}');
    debugPrint('[\ud83d\udcf8 CameraImage] Formato: ${image.format.group} (raw: ${image.format.raw})');
    debugPrint('[\ud83d\udcf8 CameraImage] Rota\u00e7\u00e3o: $rotation');
    debugPrint('[\ud83d\udcf8 CameraImage] N\u00famero de planos: ${image.planes.length}');

    for (int i = 0; i < image.planes.length; i++) {
      final plane = image.planes[i];
      debugPrint('[\ud83d\udcf8 CameraImage] Plano $i: ${plane.bytes.length} bytes, '
          'bytesPerRow: ${plane.bytesPerRow}, '
          'bytesPerPixel: ${plane.bytesPerPixel}');
    }

    debugPrint('[\ud83d\udcf8 CameraImage Debug] ==================');
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

  /// Valida se o formato de imagem est\u00e1 correto para a plataforma
  bool validateImageFormat(ImageFormatGroup format) {
    final expected = expectedImageFormat;
    final isValid = format == expected;

    if (!isValid) {
      debugPrint('[\u26a0\ufe0f PlatformCamera] Formato inesperado!');
      debugPrint('[\u26a0\ufe0f PlatformCamera] Esperado: $expected');
      debugPrint('[\u26a0\ufe0f PlatformCamera] Recebido: $format');
    }

    return isValid;
  }

  /// Retorna descri\u00e7\u00e3o detalhada da plataforma para logs
  String get platformDescription {
    final os = isIOS ? 'iOS' : (isAndroid ? 'Android' : 'Unknown');
    return '$os ${Platform.operatingSystemVersion}';
  }
}
