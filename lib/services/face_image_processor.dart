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

/// Utilitário especializado para processamento de imagens faciais.
///
/// RESPONSABILIDADES:
///  * Detecta rostos via ML Kit (usando FaceDetectionService)
///  * Faz crop com margem de segurança (20% padding)
///  * Normaliza orientação (aplica rotação EXIF)
///  * Converte para RGB (compatível com ArcFace)
///  * Suporta múltiplas estratégias de detecção (enhanced, resized)
///
/// IMPORTANTE: Este é um UTILITÁRIO, não um serviço duplicado.
/// É usado por FaceCaptureService e outros serviços de captura.
///
/// FASE 2: Consolidado como utilitário único.
class FaceImageProcessor {
  FaceImageProcessor._();

  static final FaceImageProcessor instance = FaceImageProcessor._();

  final FaceDetectionService _detection = FaceDetectionService.instance;
  final CameraImageConverter _converter = CameraImageConverter.instance;
  final PlatformCameraUtils _platformUtils = PlatformCameraUtils.instance;
  final ImageRotationHandler _rotationHandler = ImageRotationHandler.instance;
  final ImageFileProcessor _fileProcessor = ImageFileProcessor.instance;

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
      // Usar ImageFileProcessor para carregar e aplicar EXIF automaticamente
      final img.Image oriented = await _fileProcessor.loadAndOrient(file);

      Sentry.captureMessage(
        '🔄 EXIF: ${oriented.width}x${oriented.height}',
        level: SentryLevel.info,
      );

      // TENTATIVA 1: Usar arquivo ORIGINAL (recomendação do Google ML Kit)
      // InputImage.fromFile() preserva metadados EXIF automaticamente
      Sentry.captureMessage(
        '🔍 TENTATIVA 1: Detectando com arquivo original (EXIF preservado)',
        level: SentryLevel.info,
      );

      List<Face> faces;
      try {
        // Usar InputImage.fromFile() - método recomendado pela documentação
        final inputImage = InputImage.fromFile(file);
        faces = await _detection.detect(inputImage);

        // TENTATIVA 2: Se não detectar, salvar imagem orientada e melhorada
        if (faces.isEmpty) {
          Sentry.captureMessage(
            '⚠️ TENTATIVA 2: Salvando imagem orientada e melhorada',
            level: SentryLevel.warning,
          );

          final tempDir = file.parent.path;
          final tempFile = File('$tempDir/temp_enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg');

          try {
            // Aplicar melhorias
            final enhanced = _enhanceImage(oriented);
            await _fileProcessor.saveAsJpeg(enhanced, tempFile, quality: 100);

            // Usar InputImage.fromFile() novamente
            final enhancedInput = InputImage.fromFile(tempFile);
            faces = await _detection.detect(enhancedInput);

            if (faces.isNotEmpty) {
              Sentry.captureMessage(
                '✅ SUCESSO NA TENTATIVA 2: Face detectada!',
                level: SentryLevel.info,
              );
            } else {
              // TENTATIVA 3: Redimensionar imagem se for muito pequena
              Sentry.captureMessage(
                '⚠️ TENTATIVA 3: Redimensionando para 1920x1920',
                level: SentryLevel.warning,
              );

              // Se a imagem for menor que 1920, aumentar
              final maxDim = math.max(oriented.width, oriented.height);
              if (maxDim < 1920) {
                final scale = 1920 / maxDim;
                final resized = img.copyResize(
                  oriented,
                  width: (oriented.width * scale).toInt(),
                  height: (oriented.height * scale).toInt(),
                  interpolation: img.Interpolation.cubic,
                );

                await _fileProcessor.saveAsJpeg(resized, tempFile, quality: 100);

                final resizedInput = InputImage.fromFile(tempFile);
                faces = await _detection.detect(resizedInput);

                if (faces.isNotEmpty) {
                  Sentry.captureMessage(
                    '✅ SUCESSO NA TENTATIVA 3: Face detectada após redimensionamento!',
                    level: SentryLevel.info,
                  );
                }
              }
            }
          } finally {
            // Limpar arquivo temporário
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          }
        }
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
        rethrow;
      }

      if (faces.isEmpty) {
        Sentry.captureMessage(
          '❌ FALHA TOTAL: Nenhuma face após 3 tentativas (original + enhanced + resized)',
          level: SentryLevel.error,
          withScope: (scope) {
            scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
            scope.setTag('image_size', '${oriented.width}x${oriented.height}');
            scope.setTag('file_size_kb', '${(fileSize / 1024).toStringAsFixed(1)}');
            scope.setTag('detector_mode', 'accurate');
            scope.setTag('min_face_size', '15%');
          },
        );

        throw Exception('Nenhum rosto detectado. Verifique: iluminação, ângulo da câmera e distância.');
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

    // Converter CameraImage para img.Image usando YuvConverter
    img.Image base = YuvConverter.instance.toImage(image);

    // Aplicar rotação usando ImageRotationHandler
    final rotation = _rotationHandler.calculateRotation(camera: camera);
    base = _rotationHandler.applyImageRotation(base, rotation);

    // Ajustar bounding boxes dos rostos para a rotação aplicada
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final List<Face> rotatedFaces = _rotationHandler.rotateBoundingBoxes(
      faces,
      rotation,
      imageSize,
    );

    return _cropFace(base, rotatedFaces, outputSize: outputSize);
  }

  img.Image _processBytes(Uint8List bytes, List<Face> faces,
      {required int outputSize}) {
    // Usar ImageFileProcessor para decodificar e aplicar EXIF
    final img.Image baked = _fileProcessor.decodeAndOrient(bytes);

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

  /// Melhora a imagem aumentando contraste e brilho para facilitar detecção
  img.Image _enhanceImage(img.Image source) {
    // Aumentar contraste e brilho mais agressivamente
    img.Image enhanced = img.adjustColor(
      source,
      contrast: 1.5,     // 50% mais contraste
      brightness: 1.2,   // 20% mais brilho
      saturation: 1.2,   // 20% mais saturação
    );

    // Aplicar sharpening mais forte
    enhanced = img.convolution(
      enhanced,
      filter: [
        0, -1, 0,
        -1, 6, -1,  // Kernel mais agressivo
        0, -1, 0,
      ],
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

  const RectBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}
