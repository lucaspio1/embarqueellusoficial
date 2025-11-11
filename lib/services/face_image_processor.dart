// lib/services/face_image_processor.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'face_detection_service.dart';
import 'yuv_converter.dart';
import 'camera_image_converter.dart';
import 'platform_camera_utils.dart';
import 'image_rotation_handler.dart';
import 'image_file_processor.dart';

/// Resultado intermediário do processamento de uma imagem facial.
class ProcessedFaceResult {
  final img.Image croppedImage;
  final Face face;
  final String originalPath; // Caminho do ficheiro original (ou temporário corrigido)

  ProcessedFaceResult({
    required this.croppedImage,
    required this.face,
    required this.originalPath,
  });
}

/// Utilitário especializado para processamento de imagens faciais.
class FaceImageProcessor {
  FaceImageProcessor._();

  static final FaceImageProcessor instance = FaceImageProcessor._();

  final FaceDetectionService _detection = FaceDetectionService.instance;
  final CameraImageConverter _converter = CameraImageConverter.instance;
  final PlatformCameraUtils _platformUtils = PlatformCameraUtils.instance;
  final ImageRotationHandler _rotationHandler = ImageRotationHandler.instance;
  final ImageFileProcessor _fileProcessor = ImageFileProcessor.instance;

  /// Processa um arquivo de imagem (foto) - corrige EXIF, detecta e recorta face.
  ///
  /// Este é o método PRINCIPAL para processamento de fotos.
  /// Ele salva um ficheiro temporário corrigido para garantir que o MLKit
  /// no iOS o leia corretamente.
  Future<ProcessedFaceResult> processFile(
      File file, {
        int outputSize = 112,
      }) async {
    try {
      if (!await file.exists()) {
        throw Exception('Arquivo não existe: ${file.path}');
      }

      final fileSize = await file.length();
      final bool isIOS = _platformUtils.isIOS;

      Sentry.captureMessage(
        '📸 PROCESSOR START: ${(fileSize / 1024).toStringAsFixed(0)}KB',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', isIOS ? 'iOS' : 'Android');
          scope.setTag('output_size', '${outputSize}x$outputSize');
          scope.setTag('method', 'processFile');
        },
      );

      // 1. CORRIGIR EXIF PRIMEIRO (crucial para iOS)
      final img.Image oriented = await _fileProcessor.loadAndOrient(file);
      Sentry.captureMessage(
        '🔄 EXIF APPLIED: ${oriented.width}x${oriented.height}',
        level: SentryLevel.info,
      );

      // 2. Salvar imagem corrigida temporariamente
      final tempDir = file.parent.path;
      final fixedPath =
          '$tempDir/temp_fixed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final tempFile = File(fixedPath);

      try {
        // 'bakeOrientation' aplica a rotação nos píxeis
        final img.Image baked = img.bakeOrientation(oriented);
        await _fileProcessor.saveAsJpeg(baked, tempFile, quality: 100);

        Sentry.captureMessage(
          '💾 SAVED CORRECTED IMAGE: $fixedPath',
          level: SentryLevel.info,
        );

        // 3. Detectar face na imagem CORRIGIDA
        Sentry.captureMessage(
          '🔍 DETECTING on corrected image',
          level: SentryLevel.info,
        );

        // ✅ USANDO O 'face_detection_service' PURO
        final inputImage = InputImage.fromFile(tempFile);
        List<Face> faces = await _detection.detect(inputImage);

        // TENTATIVA 2: Se falhar, tentar com enhancement
        if (faces.isEmpty) {
          Sentry.captureMessage(
            '⚠️ TENTATIVA 2: Aplicando enhancement',
            level: SentryLevel.warning,
          );

          final enhanced = _enhanceImage(baked);
          await _fileProcessor.saveAsJpeg(enhanced, tempFile, quality: 100);

          final enhancedInput = InputImage.fromFile(tempFile);
          faces = await _detection.detect(enhancedInput);
          if (faces.isNotEmpty) Sentry.captureMessage('✅ SUCESSO TENTATIVA 2');
        }

        // TENTATIVA 3: Se ainda falhar, tentar com resize
        if (faces.isEmpty) {
          Sentry.captureMessage(
            '⚠️ TENTATIVA 3: Redimensionando imagem',
            level: SentryLevel.warning,
          );

          final maxDim = math.max(baked.width, baked.height);
          if (maxDim < 1920) {
            final scale = 1920 / maxDim;
            final resized = img.copyResize(
              baked,
              width: (baked.width * scale).toInt(),
              height: (baked.height * scale).toInt(),
              interpolation: img.Interpolation.cubic,
            );

            await _fileProcessor.saveAsJpeg(resized, tempFile, quality: 100);
            final resizedInput = InputImage.fromFile(tempFile);
            faces = await _detection.detect(resizedInput);
            if (faces.isNotEmpty) Sentry.captureMessage('✅ SUCESSO TENTATIVA 3');
          }
        }

        if (faces.isEmpty) {
          Sentry.captureMessage(
            '❌ FALHA TOTAL: Nenhuma face após 3 tentativas',
            level: SentryLevel.error,
          );
          throw Exception(
              'Nenhum rosto detectado. Verifique: iluminação, ângulo da câmera e distância.');
        }

        // 4. Selecionar face principal
        final primaryFace = _selectPrimaryFace(faces);

        // 5. Recortar face
        // ✅ USANDO 'baked' (imagem corrigida em memória) para o recorte
        final croppedImage =
        _cropFace(baked, [primaryFace], outputSize: outputSize);

        Sentry.captureMessage(
          '✅ PROCESSAMENTO COMPLETO: ${croppedImage.width}x${croppedImage.height}',
          level: SentryLevel.info,
        );

        return ProcessedFaceResult(
          croppedImage: croppedImage,
          face: primaryFace,
          originalPath: fixedPath, // Retorna o caminho do tempFile corrigido
        );
      } finally {
        // Não apague o tempFile para podermos depurar
        // if (await tempFile.exists()) {
        //   await tempFile.delete();
        // }
      }
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      rethrow;
    }
  }

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

  /// Processa um arquivo e retorna diretamente o recorte facial em Uint8List
  Future<Uint8List> cropFaceToBytes(String imagePath,
      {int outputSize = 112}) async {
    try {
      final file = File(imagePath);
      // ✅ CHAMA O NOVO 'processFile'
      final processedImage = await processFile(file, outputSize: outputSize);

      final bytes = Uint8List.fromList(
          img.encodeJpg(processedImage.croppedImage, quality: 95));

      Sentry.captureMessage(
        '✅ BYTES: ${bytes.length} bytes | ${(bytes.length / 1024).toStringAsFixed(1)}KB',
        level: SentryLevel.info,
      );

      return bytes;
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ### MÉTODOS AUXILIARES ###

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

  img.Image _enhanceImage(img.Image source) {
    img.Image enhanced = img.adjustColor(
      source,
      contrast: 1.5,
      brightness: 1.2,
      saturation: 1.2,
    );
    enhanced = img.convolution(
      enhanced,
      filter: [0, -1, 0, -1, 6, -1, 0, -1, 0],
      div: 2,
    );
    return enhanced;
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