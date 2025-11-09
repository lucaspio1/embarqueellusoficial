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
      await Sentry.captureMessage(
        '🖼️ PROCESSOR: Iniciando processamento de imagem facial',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
          scope.setContexts('processor_start', {
            'file_path': file.path,
            'platform': _platformUtils.platformDescription,
            'output_size': '${outputSize}x$outputSize',
          });
        },
      );

      if (!await file.exists()) {
        await Sentry.captureMessage(
          '❌ PROCESSOR: Arquivo de imagem não existe',
          level: SentryLevel.error,
          withScope: (scope) {
            scope.setContexts('file_error', {
              'file_path': file.path,
            });
          },
        );
        throw Exception('Arquivo não existe: ${file.path}');
      }

      final fileSize = await file.length();

      await Sentry.captureMessage(
        '📁 PROCESSOR: Arquivo validado',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('file_info', {
            'file_size_bytes': fileSize,
            'file_size_kb': (fileSize / 1024).toStringAsFixed(2),
            'file_size_mb': (fileSize / (1024 * 1024)).toStringAsFixed(2),
          });
        },
      );

      // ⚠️ CORREÇÃO iOS 15.5:
      // Ler e decodificar a imagem PRIMEIRO para aplicar rotação EXIF
      // ANTES de detectar faces. InputImage.fromFile() nem sempre
      // aplica EXIF corretamente no iOS.
      final bytes = await file.readAsBytes();

      await Sentry.captureMessage(
        '📊 PROCESSOR: Bytes da imagem lidos',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('bytes_read', {
            'total_bytes': bytes.length,
          });
        },
      );

      // Decodificar e aplicar orientação EXIF
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        await Sentry.captureMessage(
          '❌ PROCESSOR: Falha ao decodificar imagem',
          level: SentryLevel.error,
        );
        throw Exception('Falha ao decodificar imagem.');
      }

      await Sentry.captureMessage(
        '🖼️ PROCESSOR: Imagem decodificada',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('decoded_image', {
            'width': decoded!.width,
            'height': decoded!.height,
            'channels': decoded!.numChannels,
            'has_exif_data': decoded!.exif.data.isNotEmpty,
          });
        },
      );

      // ✅ Aplicar rotação EXIF (crítico para iOS)
      final img.Image oriented = img.bakeOrientation(decoded);

      await Sentry.captureMessage(
        '✅ PROCESSOR: Orientação EXIF aplicada',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setContexts('oriented_image', {
            'width': oriented.width,
            'height': oriented.height,
            'rotation_applied': oriented.width != decoded!.width || oriented.height != decoded.height,
          });
        },
      );

      // Salvar imagem orientada em arquivo temporário para detecção
      // (necessário porque InputImage.fromBytes pode ter problemas de formato)
      final tempDir = file.parent.path;
      final tempFile = File('$tempDir/temp_oriented_${DateTime.now().millisecondsSinceEpoch}.jpg');

      List<Face> faces;
      try {
        final orientedBytes = img.encodeJpg(oriented, quality: 95);
        await tempFile.writeAsBytes(orientedBytes);

        await Sentry.captureMessage(
          '💾 PROCESSOR: Imagem orientada salva temporariamente',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setContexts('temp_file', {
              'path': tempFile.path,
              'size_bytes': orientedBytes.length,
            });
          },
        );

        // Criar InputImage do arquivo orientado (método mais confiável)
        final inputImage = InputImage.fromFilePath(tempFile.path);

        // Agora detectar faces na imagem ORIENTADA
        faces = await _detection.detect(inputImage);

      } finally {
        // Garantir limpeza do arquivo temporário
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      if (faces.isEmpty) {
        await Sentry.captureMessage(
          '❌ PROCESSOR: CRÍTICO - NENHUM ROSTO DETECTADO na imagem!',
          level: SentryLevel.error,
          withScope: (scope) {
            scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
            scope.setTag('processor_error', 'no_face_detected');
            scope.setContexts('detection_failed', {
              'file_size_kb': (fileSize / 1024).toStringAsFixed(2),
              'file_path': file.path,
              'image_width': oriented.width,
              'image_height': oriented.height,
              'message': 'Google MLKit não encontrou nenhuma face na imagem capturada',
              'platform': _platformUtils.platformDescription,
              'exif_applied': true,
            });
          },
        );

        throw Exception('Nenhum rosto detectado na imagem.');
      }

      await Sentry.captureMessage(
        '✅ PROCESSOR: FACE DETECTADA - ${faces.length} rosto(s) encontrado(s)',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
          scope.setContexts('faces_detected', {
            'faces_count': faces.length,
            'file_size_kb': (fileSize / 1024).toStringAsFixed(2),
            'primary_face_bbox': '${faces.first.boundingBox.width.toInt()}x${faces.first.boundingBox.height.toInt()}',
            'image_width': oriented.width,
            'image_height': oriented.height,
          });
        },
      );

      // Processar com a imagem já orientada
      final result = _cropFace(oriented, faces, outputSize: outputSize);

      await Sentry.captureMessage(
        '✅ PROCESSOR: PROCESSAMENTO CONCLUÍDO - Face recortada e normalizada',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('platform', _platformUtils.isIOS ? 'iOS' : 'Android');
          scope.setContexts('processing_complete', {
            'output_width': result.width,
            'output_height': result.height,
            'output_channels': result.numChannels,
            'expected_size': '${outputSize}x$outputSize',
          });
        },
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
    Sentry.captureMessage(
      '✂️ PROCESSOR: Iniciando crop e alinhamento da face',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setContexts('crop_start', {
          'total_faces': faces.length,
          'image_width': image.width,
          'image_height': image.height,
        });
      },
    );

    final Face target = _selectPrimaryFace(faces);

    Sentry.captureMessage(
      '🎯 PROCESSOR: Face primária selecionada',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setContexts('primary_face', {
          'bbox_width': target.boundingBox.width.toInt(),
          'bbox_height': target.boundingBox.height.toInt(),
          'bbox_left': target.boundingBox.left.toInt(),
          'bbox_top': target.boundingBox.top.toInt(),
        });
      },
    );

    // 🔧 Alinhamento automático baseado em landmarks dos olhos
    final alignedImage = _alignFace(image, target);

    final RectBounds bounds = _expandBoundingBox(
      target.boundingBox,
      alignedImage.width,
      alignedImage.height,
    );

    Sentry.captureMessage(
      '📐 PROCESSOR: Bounding box expandido',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setContexts('expanded_bounds', {
          'left': bounds.left,
          'top': bounds.top,
          'width': bounds.width,
          'height': bounds.height,
        });
      },
    );

    final img.Image cropped = img.copyCrop(
      alignedImage,
      x: bounds.left,
      y: bounds.top,
      width: bounds.width,
      height: bounds.height,
    );

    final img.Image square = img.copyResizeCropSquare(
      cropped,
      size: outputSize,
    );

    Sentry.captureMessage(
      '✅ PROCESSOR: Face cropada e redimensionada',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setContexts('final_crop', {
          'output_width': square.width,
          'output_height': square.height,
          'expected_size': outputSize,
        });
      },
    );

    return _ensureRgb(square);
  }

  /// Alinha a face automaticamente baseado nos landmarks dos olhos
  img.Image _alignFace(img.Image image, Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];

    // Se não tiver landmarks dos olhos, retorna imagem original
    if (leftEye == null || rightEye == null) {
      return image;
    }

    // Calcular ângulo de rotação necessário para alinhar os olhos horizontalmente
    final dx = rightEye.position.x - leftEye.position.x;
    final dy = rightEye.position.y - leftEye.position.y;
    final angle = math.atan2(dy, dx) * 180 / math.pi;

    // Só rotacionar se o ângulo for significativo (> 2°)
    if (angle.abs() < 2.0) {
      return image;
    }

    // Rotacionar a imagem para alinhar os olhos
    return img.copyRotate(image, angle: -angle);
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
