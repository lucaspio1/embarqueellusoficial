import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Utilitário para conversão de quadros da câmera (YUV/BGRA) em RGBA.
///
/// Pensado para rodar em produção mobile (Android + iOS), levando em conta:
///  * Conversão YUV420 sem perda com manutenção da luminância.
///  * Tratamento para planos UV separados (I420) e intercalados (NV21/NV12).
///  * Suporte ao formato BGRA32 utilizado pelos dispositivos iOS.
///  * Consideração de padding de linha em cada plano.
class YuvConverter {
  const YuvConverter._();

  static const YuvConverter instance = YuvConverter._();

  /// Converte um [CameraImage] para bytes RGBA (Uint8List).
  ///
  /// Caso a câmera esteja entregando BGRA (iOS), a operação apenas realiza
  /// a reorganização para RGBA. Para Android, faz a conversão completa dos
  /// planos YUV considerando stride/padding.
  Uint8List toRgba(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.bgra8888:
        return _bgraToRgba(image);
      case ImageFormatGroup.yuv420:
        return _yuv420ToRgba(image);
      default:
        // Fallback genérico: tenta aplicar conversão YUV padrão.
        return _yuv420ToRgba(image);
    }
  }

  Uint8List _bgraToRgba(CameraImage image) {
    final plane = image.planes.first;
    final Uint8List rgba = Uint8List(image.width * image.height * 4);

    final bytesPerPixel = plane.bytesPerPixel ?? 4;
    final rowStride = plane.bytesPerRow;

    for (int y = 0; y < image.height; y++) {
      final int rowStart = y * rowStride;
      final int outRowStart = y * image.width * 4;
      for (int x = 0; x < image.width; x++) {
        final int pixelIndex = rowStart + x * bytesPerPixel;
        final int outIndex = outRowStart + x * 4;
        final int b = plane.bytes[pixelIndex];
        final int g = plane.bytes[pixelIndex + 1];
        final int r = plane.bytes[pixelIndex + 2];
        final int a = bytesPerPixel > 3 ? plane.bytes[pixelIndex + 3] : 255;
        rgba[outIndex] = r;
        rgba[outIndex + 1] = g;
        rgba[outIndex + 2] = b;
        rgba[outIndex + 3] = a;
      }
    }
    return rgba;
  }

  Uint8List _yuv420ToRgba(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final Uint8List rgba = Uint8List(width * height * 4);

    final Plane planeY = image.planes[0];
    final Plane? planeU = image.planes.length > 1 ? image.planes[1] : null;
    final Plane? planeV = image.planes.length > 2 ? image.planes[2] : null;

    final bool isInterleavedUV =
        planeU != null && planeV != null && (planeU.bytesPerPixel ?? 1) > 1;
    final bool hasSeparateUV = planeU != null && planeV != null && !isInterleavedUV;

    final int uvRowStride = planeU?.bytesPerRow ?? planeY.bytesPerRow;
    final int uvPixelStride = planeU?.bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      final int uvRow = (y >> 1) * uvRowStride;
      final int yRow = y * planeY.bytesPerRow;
      for (int x = 0; x < width; x++) {
        final int uvColumn = (x >> 1) * uvPixelStride;
        final int yIndex = yRow + x;

        int u = 128;
        int v = 128;

        if (planeU != null) {
          if (isInterleavedUV) {
            final int index = uvRow + uvColumn;
            // NV21 (VU) costuma aparecer em dispositivos Samsung.
            final bool isNv21 = _isNV21(image.format.raw);
            if (isNv21) {
              v = planeU.bytes[index];
              u = planeU.bytes[math.min(index + 1, planeU.bytes.length - 1)];
            } else {
              u = planeU.bytes[index];
              v = planeU.bytes[math.min(index + 1, planeU.bytes.length - 1)];
            }
          } else if (hasSeparateUV && planeV != null) {
            final int uIndex = uvRow + uvColumn;
            final int vIndex = uvRow + uvColumn;
            u = planeU.bytes[uIndex];
            v = planeV.bytes[vIndex];
          } else if (planeV != null) {
            final int index = uvRow + uvColumn;
            u = planeU.bytes[index];
            v = planeV.bytes[index];
          }
        }

        final int yValue = planeY.bytes[yIndex];
        final int outIndex = (y * width + x) * 4;

        final double yf = yValue.toDouble();
        final double uf = (u - 128).toDouble();
        final double vf = (v - 128).toDouble();

        double r = yf + 1.403 * vf;
        double g = yf - 0.344 * uf - 0.714 * vf;
        double b = yf + 1.770 * uf;

        rgba[outIndex] = _clampToByte(r);
        rgba[outIndex + 1] = _clampToByte(g);
        rgba[outIndex + 2] = _clampToByte(b);
        rgba[outIndex + 3] = 255;
      }
    }

    return rgba;
  }

  int _clampToByte(double value) {
    return value < 0.0
        ? 0
        : value > 255.0
            ? 255
            : value.round();
  }

  bool _isNV21(int rawFormat) {
    const nv21Formats = {17, 256};
    return nv21Formats.contains(rawFormat);
  }
}
