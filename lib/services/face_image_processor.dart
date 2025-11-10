import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

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

/// Responsável por preparar imagens para a extração de embeddings:
///  * Detecta rostos via MLKit.
///  * Faz crop com margem segura.
///  * Normaliza orientação e converte para RGB.
class FaceImageProcessor {
  FaceImageProcessor._();

  static final FaceImageProcessor instance = FaceImageProcessor._();

  final FaceDetectionService _detection = FaceDetectionService.instance;
  final CameraImageConverter _converter = CameraImageConverter.instance;
  final PlatformCameraUtils _platformUtils = PlatformCameraUtils.instance;

  /// Processa um arquivo de imagem (por exemplo, foto capturada) e retorna a
  /// imagem já recortada/normalizada para uso pelo ArcFace.
  ///
  /// IMPORTANTE: Este método lê e decodifica a imagem ANTES de detectar faces,
  /// garantindo que a rotação EXIF seja aplicada corretamente no iOS.
  Future<img.Image> processFile(File file, {int outputSize = 112}) async {
    try {
      if (!await file.exists()) {
        throw Exception('Arquivo não existe: ${file.path}');
      }

      final fileSize = await file.length();

      Sentry.captureMessage(
        '📸 PROCESSOR START: ${(fileSize / 1024).toStringAsFixed(0)}KB',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
          scope.setTag('output_size', '${outputSize}x$outputSize');
        },
      );

      // ⚠️ CORREÇÃO iOS 15.5:
      // Ler e decodificar a imagem PRIMEIRO para aplicar rotação EXIF
      // ANTES de detectar faces. InputImage.fromFile() nem sempre
      // aplica EXIF corretamente no iOS.
      final bytes = await file.readAsBytes();

      // Decodificar e aplicar orientação EXIF
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw Exception('Falha ao decodificar imagem.');
      }

      // ✅ Aplicar rotação EXIF (crítico para iOS)
      final img.Image oriented = img.bakeOrientation(decoded);

      Sentry.captureMessage(
        '🔄 EXIF: ${oriented.width}x${oriented.height}',
        level: SentryLevel.info,
      );

      // Salvar imagem orientada em arquivo temporário para detecção
      // (necessário porque InputImage.fromBytes pode ter problemas de formato)
      final tempDir = file.parent.path;
      final tempFile = File('$tempDir/temp_oriented_${DateTime.now().millisecondsSinceEpoch}.jpg');

      List<Face> faces;
      try {
        final orientedBytes = img.encodeJpg(oriented, quality: 95);
        await tempFile.writeAsBytes(orientedBytes);

        // Criar InputImage do arquivo orientado (método mais confiável)
        final inputImage = InputImage.fromFilePath(tempFile.path);

        // TENTATIVA 1: Detectar faces na imagem orientada original
        faces = await _detection.detect(inputImage);

        // Se não detectar faces, tentar com melhorias de imagem
        if (faces.isEmpty) {
          Sentry.captureMessage(
            '⚠️ TENTATIVA 2: Aplicando melhorias (contraste +30%, brilho +10%)',
            level: SentryLevel.warning,
          );

          // Tentar com aumento de contraste e brilho
          final enhanced = _enhanceImage(oriented);
          final enhancedBytes = img.encodeJpg(enhanced, quality: 95);
          await tempFile.writeAsBytes(enhancedBytes);

          final enhancedInput = InputImage.fromFilePath(tempFile.path);
          faces = await _detection.detect(enhancedInput);

          if (faces.isNotEmpty) {
            Sentry.captureMessage(
              '✅ SUCESSO NA TENTATIVA 2: Face detectada com imagem melhorada!',
              level: SentryLevel.info,
            );
          }
        }

      } finally {
        // Garantir limpeza do arquivo temporário
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      if (faces.isEmpty) {
        Sentry.captureMessage(
          '❌ FALHA TOTAL: Nenhuma face detectada após 2 tentativas',
          level: SentryLevel.error,
          withScope: (scope) {
            scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
            scope.setTag('image_size', '${oriented.width}x${oriented.height}');
            scope.setTag('file_size_kb', '${(fileSize / 1024).toStringAsFixed(1)}');
          },
        );

        throw Exception('Nenhum rosto detectado na imagem.');
      }

      Sentry.captureMessage(
        '✅ CROP: Iniciando recorte | Face ${faces.first.boundingBox.width.toInt()}x${faces.first.boundingBox.height.toInt()}',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('faces_count', '${faces.length}');
          scope.setTag('padding', '20%');
        },
      );

      // Processar com a imagem já orientada
      final result = _cropFace(oriented, faces, outputSize: outputSize);

      Sentry.captureMessage(
        '✅ PROCESSAMENTO COMPLETO: ${result.width}x${result.height} | RGB',
        level: SentryLevel.info,
      );

      return result;
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro CRÍTICO ao processar arquivo de imagem',
          'file_path': file.path,
          'platform': _platformUtils.platformDescription,
        }),
      );

      rethrow;
    }
  }

  /// Processa a imagem de câmera em tempo real.
  ///
  /// Retorna `null` quando nenhum rosto é detectado no quadro.
  ///
  /// [camera] - Descrição da câmera usada (necessário para calcular rotação correta)
  /// [enableDebugLogs] - Habilita logs detalhados de debug (útil para troubleshooting)
  Future<img.Image?> processCameraImage(
    CameraImage image, {
    required CameraDescription camera,
    bool enableDebugLogs = false,
    int outputSize = 112,
  }) async {
    // Usar conversor centralizado que aplica rotação correta automaticamente
    final input = _converter.convert(
      image: image,
      camera: camera,
      enableDebugLogs: enableDebugLogs,
    );

    final faces = await _detection.detect(input);
    if (faces.isEmpty) {
      return null;
    }

    // Converter CameraImage para RGBA usando YuvConverter
    final Uint8List rgba = YuvConverter.instance.toRgba(image);
    img.Image base = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );

    // Aplicar rotação calculada pelo conversor
    final rotation = _platformUtils.getImageRotation(camera: camera);
    base = _applyRotation(base, rotation);

    // Ajustar bounding boxes dos rostos para a rotação aplicada
    final List<Face> rotatedFaces =
        faces.map((f) => _rotateFaceBoundingBox(f, rotation, image)).toList();

    return _cropFace(base, rotatedFaces, outputSize: outputSize);
  }

  img.Image _processBytes(Uint8List bytes, List<Face> faces,
      {required int outputSize}) {
    Sentry.captureMessage(
      '🔄 PROCESSOR: Decodificando bytes da imagem',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setContexts('decode_start', {
          'bytes_length': bytes.length,
        });
      },
    );

    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      Sentry.captureMessage(
        '❌ PROCESSOR: Falha ao decodificar imagem',
        level: SentryLevel.error,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
          scope.setContexts('decode_error', {
            'bytes_length': bytes.length,
          });
        },
      );
      throw Exception('Falha ao decodificar imagem.');
    }

    Sentry.captureMessage(
      '✅ PROCESSOR: Imagem decodificada',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setContexts('decoded_image', {
          'width': decoded!.width,
          'height': decoded!.height,
          'channels': decoded!.numChannels,
        });
      },
    );

    final img.Image baked = img.bakeOrientation(decoded!);

    Sentry.captureMessage(
      '🔄 PROCESSOR: Orientação da imagem normalizada',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setContexts('baked_image', {
          'width': baked.width,
          'height': baked.height,
        });
      },
    );

    return _cropFace(baked, faces, outputSize: outputSize);
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

  /// Processa um arquivo e retorna diretamente o recorte facial em Uint8List
  /// Pronto para gerar embeddings faciais.
  Future<Uint8List> cropFaceToBytes(String imagePath, {int outputSize = 112}) async {
    try {
      final file = File(imagePath);
      final processedImage = await processFile(file, outputSize: outputSize);

      // Converter para JPEG com alta qualidade
      final bytes = Uint8List.fromList(img.encodeJpg(processedImage, quality: 95));

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
    const double padding = 0.20; // 20% de margem de cada lado
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
        final pixel = source.getPixel(x, y);
        rgb.setPixelRgb(x, y, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
      }
    }
    return rgb;
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

  /// Melhora a imagem aumentando contraste e brilho para facilitar detecção
  img.Image _enhanceImage(img.Image source) {
    // Aumentar contraste (1.3 = 30% mais contraste)
    img.Image enhanced = img.adjustColor(
      source,
      contrast: 1.3,
      brightness: 1.1,
      saturation: 1.1,
    );

    // Aplicar sharpening para melhorar bordas
    enhanced = img.convolution(
      enhanced,
      filter: [
        0, -1, 0,
        -1, 5, -1,
        0, -1, 0,
      ],
      div: 1,
    );

    return enhanced;
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
