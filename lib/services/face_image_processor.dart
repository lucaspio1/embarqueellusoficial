// lib/services/face_image_processor.dart
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'face_detection_service.dart';
import 'yuv_converter.dart';
import 'camera_image_converter.dart';
import 'platform_camera_utils.dart';
import 'image_rotation_handler.dart';

/// Resultado intermediário do processamento de uma imagem facial.
class ProcessedFaceResult {
  final img.Image croppedImage;
  final Face face;
  final String originalPath; // Caminho do ficheiro original ou 'live_stream' para câmera

  ProcessedFaceResult({
    required this.croppedImage,
    required this.face,
    required this.originalPath,
  });
}

/// Utilitário especializado para processamento de imagens faciais da CÂMERA AO VIVO.
///
/// IMPORTANTE: Este serviço agora é usado APENAS para processamento de stream da câmera.
/// O processamento de fotos estáticas foi migrado para código nativo via NativeFaceService.
class FaceImageProcessor {
  FaceImageProcessor._();

  static final FaceImageProcessor instance = FaceImageProcessor._();

  final FaceDetectionService _detection = FaceDetectionService.instance;
  final CameraImageConverter _converter = CameraImageConverter.instance;
  final PlatformCameraUtils _platformUtils = PlatformCameraUtils.instance;
  final ImageRotationHandler _rotationHandler = ImageRotationHandler.instance;

  /// Processa a imagem de câmera em tempo real.
  /// ✅ RETORNA ProcessedFaceResult
  Future<ProcessedFaceResult?> processCameraImage(
      CameraImage image, {
        required CameraDescription camera,
        bool enableDebugLogs = false,
        int outputSize = 112,
      }) async {
    final input = _converter.convert(
      image: image,
      camera: camera,
      enableDebugLogs: enableDebugLogs,
    );

    // ✅ USANDO O 'face_detection_service' PURO
    final faces = await _detection.detect(input);
    if (faces.isEmpty) {
      return null;
    }

    img.Image base = YuvConverter.instance.toImage(image);
    final rotation = _rotationHandler.calculateRotation(camera: camera);
    base = _rotationHandler.applyImageRotation(base, rotation);

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final List<Face> rotatedFaces = _rotationHandler.rotateBoundingBoxes(
      faces,
      rotation,
      imageSize,
    );

    final (img.Image croppedImage, Face primaryFace) = _cropFaceTupla(
      base,
      rotatedFaces,
      outputSize: outputSize,
    );

    return ProcessedFaceResult(
      croppedImage: croppedImage,
      face: primaryFace,
      originalPath: 'live_stream',
    );
  }

  // ### MÉTODOS AUXILIARES (usados por processCameraImage) ###

  /// Retorna (img.Image, Face)
  (img.Image, Face) _cropFaceTupla(
      img.Image image,
      List<Face> faces, {
        required int outputSize,
      }) {
    final Face target = _selectPrimaryFace(faces);
    final img.Image cropped =
    _cropFace(image, [target], outputSize: outputSize);
    return (cropped, target);
  }

  img.Image _cropFace(img.Image image, List<Face> faces,
      {required int outputSize}) {
    final Face target = _selectPrimaryFace(faces);

    final RectBounds bounds = _expandBoundingBox(
      target.boundingBox,
      image.width,
      image.height,
    );

    final img.Image cropped = img.copyCrop(
      image,
      x: bounds.left,
      y: bounds.top,
      width: bounds.width,
      height: bounds.height,
    );

    final img.Image square = img.copyResizeCropSquare(
      cropped,
      size: outputSize,
    );

    return _ensureRgb(square);
  }

  Face _selectPrimaryFace(List<Face> faces) {
    return faces.reduce((value, element) {
      final double currentArea =
          element.boundingBox.width * element.boundingBox.height;
      final double bestArea =
          value.boundingBox.width * value.boundingBox.height;
      return currentArea > bestArea ? element : value;
    });
  }

  RectBounds _expandBoundingBox(Rect rect, int width, int height) {
    const double padding = 0.20; // 20%
    final double centerX = rect.center.dx;
    final double centerY = rect.center.dy;
    final double halfSize = math.max(rect.width, rect.height) / 2;
    final double expandedHalf = halfSize * (1 + padding);

    double left = (centerX - expandedHalf).clamp(0, width - 1).toDouble();
    double top = (centerY - expandedHalf).clamp(0, height - 1).toDouble();
    double right = (centerX + expandedHalf).clamp(left + 1, width.toDouble());
    double bottom = (centerY + expandedHalf).clamp(top + 1, height.toDouble());

    return RectBounds(
      left: left.floor(),
      top: top.floor(),
      width: math.max(1, (right - left).ceil()),
      height: math.max(1, (bottom - top).ceil()),
    );
  }

  img.Image _ensureRgb(img.Image source) {
    if (source.numChannels == 3) return source;
    final img.Image rgb = img.Image(
      width: source.width,
      height: source.height,
      numChannels: 3,
    );
    for (int y = 0; y < source.height; y++) {
      for (int x = 0; x < source.width; x++) {
        final pixel = source.getPixel(x, y);
        rgb.setPixelRgb(
            x, y, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
      }
    }
    return rgb;
  }
}

class RectBounds {
  final int left;
  final int top;
  final int width;
  final int height;
  const RectBounds(
      {required this.left,
        required this.top,
        required this.width,
        required this.height});
}