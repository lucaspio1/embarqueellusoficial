import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'face_detection_service.dart';
import 'yuv_converter.dart';

/// Responsável por preparar imagens para a extração de embeddings:
///  * Detecta rostos via MLKit.
///  * Faz crop com margem segura.
///  * Normaliza orientação e converte para RGB.
class FaceImageProcessor {
  FaceImageProcessor._();

  static final FaceImageProcessor instance = FaceImageProcessor._();

  final FaceDetectionService _detection = FaceDetectionService.instance;

  /// Processa um arquivo de imagem (por exemplo, foto capturada) e retorna a
  /// imagem já recortada/normalizada para uso pelo ArcFace.
  Future<img.Image> processFile(File file, {int outputSize = 112}) async {
    final faces = await _detection.detectFromFile(file);
    if (faces.isEmpty) {
      throw Exception('Nenhum rosto detectado na imagem.');
    }

    final bytes = await file.readAsBytes();
    return _processBytes(bytes, faces, outputSize: outputSize);
  }

  /// Processa a imagem de câmera em tempo real.
  ///
  /// Retorna `null` quando nenhum rosto é detectado no quadro.
  Future<img.Image?> processCameraImage(
    CameraImage image, {
    required InputImageRotation rotation,
    int outputSize = 112,
  }) async {
    final input = _inputImageFromCameraImage(image, rotation);
    final faces = await _detection.detect(input);
    if (faces.isEmpty) {
      return null;
    }

    final Uint8List rgba = YuvConverter.instance.toRgba(image);
    img.Image base = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: rgba,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );

    base = _applyRotation(base, rotation);
    final List<Face> rotatedFaces =
        faces.map((f) => _rotateFaceBoundingBox(f, rotation, image)).toList();
    return _cropFace(base, rotatedFaces, outputSize: outputSize);
  }

  img.Image _processBytes(Uint8List bytes, List<Face> faces,
      {required int outputSize}) {
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Falha ao decodificar imagem.');
    }

    decoded = img.bakeOrientation(decoded);
    return _cropFace(decoded, faces, outputSize: outputSize);
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
    const double padding = 0.28; // margem segura para evitar cortes
    final double centerX = rect.center.dx;
    final double centerY = rect.center.dy;
    final double halfSize = math.max(rect.width, rect.height) / 2;
    final double expandedHalf = halfSize * (1 + padding);

    double left = centerX - expandedHalf;
    double top = centerY - expandedHalf;
    double right = centerX + expandedHalf;
    double bottom = centerY + expandedHalf;

    left = left.clamp(0, width - 1).toDouble();
    top = top.clamp(0, height - 1).toDouble();
    right = right.clamp(left + 1, width.toDouble());
    bottom = bottom.clamp(top + 1, height.toDouble());

    final int finalLeft = left.floor();
    final int finalTop = top.floor();
    final int finalRight = right.ceil();
    final int finalBottom = bottom.ceil();

    return RectBounds(
      left: finalLeft,
      top: finalTop,
      width: math.max(1, finalRight - finalLeft),
      height: math.max(1, finalBottom - finalTop),
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
        final int pixel = source.getPixel(x, y);
        rgb.setPixelRgb(x, y, pixel.r, pixel.g, pixel.b);
      }
    }
    return rgb;
  }

  InputImage _inputImageFromCameraImage(
      CameraImage image, InputImageRotation rotation) {
    final WriteBuffer buffer = WriteBuffer();
    for (final Plane plane in image.planes) {
      buffer.putUint8List(plane.bytes);
    }
    final Uint8List bytes = buffer.done().buffer.asUint8List();

    final InputImageFormat? format = _mapInputFormat(image.format.raw);
    if (format == null) {
      throw Exception('Formato de imagem não suportado: ${image.format.raw}');
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  InputImageFormat? _mapInputFormat(int raw) {
    switch (raw) {
      case 17:
        return InputImageFormat.nv21;
      case 35:
        return InputImageFormat.yuv_420_888;
      case 842094169:
        return InputImageFormat.yuv420;
      case 1111970369:
        return InputImageFormat.bgra8888;
      default:
        return null;
    }
  }

  img.Image _applyRotation(img.Image image, InputImageRotation rotation) {
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

  Face _rotateFaceBoundingBox(
      Face face, InputImageRotation rotation, CameraImage image) {
    final Rect box = face.boundingBox;
    final double width = image.width.toDouble();
    final double height = image.height.toDouble();

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
}

class RectBounds {
  final int left;
  final int top;
  final int width;
  final int height;

  const RectBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}
