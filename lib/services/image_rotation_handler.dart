import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:image/image.dart' as img;
import 'package:sentry_flutter/sentry_flutter.dart';

/// Handler centralizado para todas as operações de rotação de imagem.
///
/// Responsabilidades:
/// - Calcular rotação correta baseada em câmera/device/plataforma
/// - Aplicar rotação a imagens (img.Image)
/// - Transformar bounding boxes de faces para rotações
/// - Fornecer conversões entre formatos de rotação
///
/// Consolidação da FASE 3: Elimina duplicação de lógica de rotação
/// espalhada entre PlatformCameraUtils e FaceImageProcessor.
class ImageRotationHandler {
  ImageRotationHandler._();

  static final ImageRotationHandler instance = ImageRotationHandler._();

  /// Retorna true se estiver executando no iOS
  bool get isIOS => Platform.isIOS;

  /// Retorna true se estiver executando no Android
  bool get isAndroid => Platform.isAndroid;

  // ==================== CÁLCULO DE ROTAÇÃO ====================

  /// Calcula a rotação correta do InputImage baseado na câmera e orientação do device.
  ///
  /// Para câmera traseira:
  /// - Android: geralmente rotation0deg (landscape) ou rotation90deg (portrait)
  /// - iOS: pode variar, precisa ajuste baseado em sensorOrientation
  ///
  /// [camera] - Descrição da câmera (lensDirection, sensorOrientation)
  /// [deviceOrientation] - Orientação atual do dispositivo
  InputImageRotation calculateRotation({
    required CameraDescription camera,
    DeviceOrientation? deviceOrientation,
  }) {
    // Orientação padrão: portrait up
    final orientation = deviceOrientation ?? DeviceOrientation.portraitUp;

    // Sensor orientation da câmera (graus: 0, 90, 180, 270)
    final int sensorOrientation = camera.sensorOrientation;

    // Log de debug
    debugPrint('[🔄 RotationHandler] Plataforma: ${isIOS ? "iOS" : "Android"}');
    debugPrint('[🔄 RotationHandler] Câmera: ${camera.lensDirection}');
    debugPrint('[🔄 RotationHandler] Sensor Orientation: $sensorOrientation°');
    debugPrint('[🔄 RotationHandler] Device Orientation: $orientation');

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
          'rotation_degrees': rotationToDegrees(rotation),
          'sensor_orientation': '$sensorOrientation°',
          'camera_direction': camera.lensDirection.toString(),
        });
      },
    );

    debugPrint('[🔄 RotationHandler] Rotação InputImage: $rotation');
    return rotation;
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
            'rotation_degrees': rotationToDegrees(result),
          });
        },
      );

      return result;
    }

    // Câmera frontal iOS
    result = rotationFromDegrees(sensorOrientation);

    Sentry.captureMessage(
      '✅ iOS ROTATION: Rotação da câmera frontal calculada',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setTag('platform', 'iOS');
        scope.setTag('camera_type', 'front');
        scope.setContexts('ios_front_rotation', {
          'sensor_orientation': '$sensorOrientation°',
          'rotation_applied': result.toString(),
          'rotation_degrees': rotationToDegrees(result),
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
    return rotationFromDegrees(sensorOrientation);
  }

  // ==================== APLICAÇÃO DE ROTAÇÃO ====================

  /// Aplica rotação a uma imagem (img.Image)
  ///
  /// [image] - Imagem a ser rotacionada
  /// [rotation] - Rotação a ser aplicada
  ///
  /// Retorna nova imagem rotacionada (ou a original se rotation0deg)
  img.Image applyImageRotation(img.Image image, InputImageRotation rotation) {
    switch (rotation) {
      case InputImageRotation.rotation0deg:
        return image;
      case InputImageRotation.rotation90deg:
        return img.copyRotate(image, angle: 90);
      case InputImageRotation.rotation180deg:
        return img.copyRotate(image, angle: 180);
      case InputImageRotation.rotation270deg:
        return img.copyRotate(image, angle: 270);
    }
  }

  // ==================== TRANSFORMAÇÃO DE BOUNDING BOXES ====================

  /// Ajusta bounding box de face para a rotação aplicada
  ///
  /// [face] - Face com bounding box original
  /// [rotation] - Rotação aplicada à imagem
  /// [imageSize] - Tamanho da imagem original
  ///
  /// Retorna nova Face com bounding box transformado
  Face rotateBoundingBox(
    Face face,
    InputImageRotation rotation,
    Size imageSize,
  ) {
    final Rect box = face.boundingBox;
    final double width = imageSize.width;
    final double height = imageSize.height;

    Rect mapped;
    switch (rotation) {
      case InputImageRotation.rotation0deg:
        mapped = box;
        break;
      case InputImageRotation.rotation90deg:
        mapped = Rect.fromLTWH(
          height - box.bottom,
          box.left,
          box.height,
          box.width,
        );
        break;
      case InputImageRotation.rotation180deg:
        mapped = Rect.fromLTWH(
          width - box.right,
          height - box.bottom,
          box.width,
          box.height,
        );
        break;
      case InputImageRotation.rotation270deg:
        mapped = Rect.fromLTWH(
          box.top,
          width - box.right,
          box.height,
          box.width,
        );
        break;
    }

    return Face(
      boundingBox: mapped,
      headEulerAngleX: face.headEulerAngleX,
      headEulerAngleY: face.headEulerAngleY,
      headEulerAngleZ: face.headEulerAngleZ,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      smilingProbability: face.smilingProbability,
      trackingId: face.trackingId,
      landmarks: face.landmarks,
      contours: face.contours,
    );
  }

  /// Batch rotate: aplica rotação a múltiplas faces
  ///
  /// [faces] - Lista de faces a serem transformadas
  /// [rotation] - Rotação aplicada
  /// [imageSize] - Tamanho da imagem original
  ///
  /// Retorna lista de faces com bounding boxes transformados
  List<Face> rotateBoundingBoxes(
    List<Face> faces,
    InputImageRotation rotation,
    Size imageSize,
  ) {
    return faces.map((f) => rotateBoundingBox(f, rotation, imageSize)).toList();
  }

  // ==================== CONVERSÕES DE FORMATO ====================

  /// Converte InputImageRotation para graus
  int rotationToDegrees(InputImageRotation rotation) {
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

  /// Converte graus (sensorOrientation) para InputImageRotation
  InputImageRotation rotationFromDegrees(int degrees) {
    switch (degrees) {
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
        debugPrint('[⚠️ RotationHandler] Graus inválidos: $degrees°, usando 90°');
        return InputImageRotation.rotation90deg;
    }
  }
}
