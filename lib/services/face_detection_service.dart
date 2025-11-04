import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Singleton responsável por detectar rostos utilizando o Google MLKit.
///
/// A implementação mantém uma única instância do [FaceDetector] configurada
/// para o modo FAST, habilitando landmarks, classificação e tracking – conforme
/// requisitos de produção.
class FaceDetectionService {
  FaceDetectionService._();

  static final FaceDetectionService instance = FaceDetectionService._();

  FaceDetector? _faceDetector;

  FaceDetector _ensureDetector() {
    if (_faceDetector != null) return _faceDetector!;
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: true,
      ),
    );
    return _faceDetector!;
  }

  /// Detecta rostos em uma [InputImage].
  Future<List<Face>> detect(InputImage image) {
    final detector = _ensureDetector();
    return detector.processImage(image);
  }

  /// Detecta rostos em uma imagem de arquivo físico.
  Future<List<Face>> detectFromFile(File file) {
    final input = InputImage.fromFile(file);
    return detect(input);
  }

  /// Detecta rostos a partir de um caminho de arquivo.
  Future<List<Face>> detectFromPath(String path) {
    final input = InputImage.fromFilePath(path);
    return detect(input);
  }

  /// Libera recursos do detector.
  Future<void> dispose() async {
    await _faceDetector?.close();
    _faceDetector = null;
  }
}
