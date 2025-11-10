import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Resultado da captura/reconhecimento facial
class FaceCameraResult {
  /// Se a operação foi bem-sucedida
  final bool success;

  /// Caminho(s) do(s) arquivo(s) de imagem capturado(s)
  final List<String>? imagePaths;

  /// Imagem(ns) processada(s) (recortada e normalizada)
  final List<img.Image>? processedImages;

  /// Bytes da(s) imagem(ns) processada(s)
  final List<Uint8List>? imageBytes;

  /// Embedding(s) facial extraído(s)
  final List<List<double>>? embeddings;

  /// Dados do aluno reconhecido (apenas para modo recognition)
  final Map<String, dynamic>? recognizedPerson;

  /// Score de confiança do reconhecimento (0.0 - 1.0)
  final double? confidenceScore;

  /// Distância L2 do reconhecimento
  final double? distance;

  /// Mensagem de erro (se houver)
  final String? errorMessage;

  const FaceCameraResult({
    required this.success,
    this.imagePaths,
    this.processedImages,
    this.imageBytes,
    this.embeddings,
    this.recognizedPerson,
    this.confidenceScore,
    this.distance,
    this.errorMessage,
  });

  /// Construtor para sucesso no cadastro
  factory FaceCameraResult.enrollment({
    required List<String> imagePaths,
    required List<img.Image> processedImages,
    List<List<double>>? embeddings,
  }) {
    return FaceCameraResult(
      success: true,
      imagePaths: imagePaths,
      processedImages: processedImages,
      embeddings: embeddings,
    );
  }

  /// Construtor para sucesso no reconhecimento
  factory FaceCameraResult.recognition({
    required Map<String, dynamic> recognizedPerson,
    required double confidenceScore,
    required double distance,
    String? imagePath,
    img.Image? processedImage,
  }) {
    return FaceCameraResult(
      success: true,
      recognizedPerson: recognizedPerson,
      confidenceScore: confidenceScore,
      distance: distance,
      imagePaths: imagePath != null ? [imagePath] : null,
      processedImages: processedImage != null ? [processedImage] : null,
    );
  }

  /// Construtor para falha
  factory FaceCameraResult.failure({
    required String errorMessage,
  }) {
    return FaceCameraResult(
      success: false,
      errorMessage: errorMessage,
    );
  }

  /// Construtor para cancelamento
  factory FaceCameraResult.cancelled() {
    return const FaceCameraResult(
      success: false,
      errorMessage: 'Operação cancelada pelo usuário',
    );
  }

  /// Pega a primeira imagem processada (útil para modo simples)
  img.Image? get firstProcessedImage {
    return processedImages?.isNotEmpty == true ? processedImages!.first : null;
  }

  /// Pega o primeiro embedding (útil para modo simples)
  List<double>? get firstEmbedding {
    return embeddings?.isNotEmpty == true ? embeddings!.first : null;
  }

  /// Pega o primeiro caminho de imagem
  String? get firstImagePath {
    return imagePaths?.isNotEmpty == true ? imagePaths!.first : null;
  }
}
