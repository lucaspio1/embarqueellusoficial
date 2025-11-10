import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:sentry_flutter/sentry_flutter.dart';

/// Processador centralizado para carregar e normalizar imagens de arquivo.
///
/// Responsabilidades:
/// - Carregar arquivos de imagem
/// - Decodificar bytes de imagem
/// - Aplicar rotação EXIF (crítico para iOS)
/// - Tratamento de erros centralizado
/// - Logs Sentry consolidados
///
/// Consolidação da FASE 3: Elimina duplicação de lógica de EXIF handling
/// espalhada em múltiplos métodos de FaceImageProcessor.
class ImageFileProcessor {
  ImageFileProcessor._();

  static final ImageFileProcessor instance = ImageFileProcessor._();

  /// Carrega arquivo, decodifica e aplica orientação EXIF
  ///
  /// [file] - Arquivo de imagem a ser processado
  ///
  /// Retorna imagem decodificada com orientação EXIF aplicada.
  /// Lança exceção se arquivo não existir ou falhar na decodificação.
  ///
  /// IMPORTANTE: Aplicar EXIF é crítico para iOS 15.5+, onde InputImage.fromFile()
  /// nem sempre respeita a orientação original da imagem.
  Future<img.Image> loadAndOrient(File file) async {
    if (!await file.exists()) {
      throw Exception('Arquivo não existe: ${file.path}');
    }

    final fileSize = await file.length();

    Sentry.captureMessage(
      '📂 FILE: Carregando arquivo (${(fileSize / 1024).toStringAsFixed(0)}KB)',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setContexts('file_load', {
          'file_path': file.path,
          'file_size_bytes': fileSize,
        });
      },
    );

    final bytes = await file.readAsBytes();

    Sentry.captureMessage(
      '📦 FILE: Bytes lidos (${bytes.length} bytes)',
      level: SentryLevel.info,
    );

    return decodeAndOrient(bytes);
  }

  /// Decodifica bytes e aplica orientação EXIF
  ///
  /// [bytes] - Bytes da imagem a serem decodificados
  ///
  /// Retorna imagem decodificada com orientação EXIF aplicada.
  /// Lança exceção se falhar na decodificação.
  ///
  /// Este método é útil quando você já tem os bytes da imagem
  /// e não precisa carregar de um arquivo.
  img.Image decodeAndOrient(Uint8List bytes) {
    Sentry.captureMessage(
      '🔄 DECODE: Decodificando bytes da imagem',
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
        '❌ DECODE: Falha ao decodificar imagem',
        level: SentryLevel.error,
        withScope: (scope) {
          scope.setContexts('decode_error', {
            'bytes_length': bytes.length,
          });
        },
      );
      throw Exception('Falha ao decodificar imagem.');
    }

    Sentry.captureMessage(
      '✅ DECODE: Imagem decodificada',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setContexts('decoded_image', {
          'width': decoded!.width,
          'height': decoded!.height,
          'channels': decoded!.numChannels,
        });
      },
    );

    // ✅ Aplicar rotação EXIF (crítico para iOS)
    final img.Image baked = img.bakeOrientation(decoded);

    Sentry.captureMessage(
      '🔄 EXIF: Orientação normalizada',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setContexts('baked_image', {
          'width': baked.width,
          'height': baked.height,
          'exif_applied': decoded.width != baked.width || decoded.height != baked.height,
        });
      },
    );

    return baked;
  }

  /// Decodifica bytes SEM aplicar orientação EXIF
  ///
  /// [bytes] - Bytes da imagem
  ///
  /// Use este método apenas quando você não deseja aplicar a rotação EXIF.
  /// Na maioria dos casos, prefira [decodeAndOrient].
  img.Image decodeOnly(Uint8List bytes) {
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Falha ao decodificar imagem.');
    }
    return decoded;
  }

  /// Salva imagem em arquivo
  ///
  /// [image] - Imagem a ser salva
  /// [file] - Arquivo de destino
  /// [quality] - Qualidade JPEG (1-100, padrão: 95)
  ///
  /// Retorna File salvo
  Future<File> saveAsJpeg(img.Image image, File file, {int quality = 95}) async {
    final bytes = img.encodeJpg(image, quality: quality);
    await file.writeAsBytes(bytes);

    Sentry.captureMessage(
      '💾 FILE: Imagem salva',
      level: SentryLevel.info,
      withScope: (scope) {
        scope.setContexts('file_save', {
          'file_path': file.path,
          'width': image.width,
          'height': image.height,
          'quality': quality,
          'size_bytes': bytes.length,
        });
      },
    );

    return file;
  }
}
