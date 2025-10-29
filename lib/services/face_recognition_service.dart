// lib/services/face_recognition_service.dart - COMPLETAMENTE REFEITO
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:embarqueellus/database/database_helper.dart';

/// ✅ NOVO SERVIÇO COM MobileFaceNet - MAIS EFICIENTE
class FaceRecognitionService {
  static final FaceRecognitionService instance = FaceRecognitionService._internal();
  FaceRecognitionService._internal();

  Interpreter? _interpreter;
  bool _modelLoaded = false;

  // ✅ CONFIGURAÇÕES OTIMIZADAS
  static const double SIMILARITY_THRESHOLD = 0.6; // Pode ajustar depois
  static const int INPUT_SIZE = 112; // MobileFaceNet usa 112x112
  static const int EMBEDDING_SIZE = 192; // Dimensões do embedding

  Future<void> init() async {
    if (_modelLoaded) return;
    await _loadMobileFaceNet();
  }

  Future<void> _loadMobileFaceNet() async {
    try {
      print('🧠 Carregando modelo ArcFace...');

      final options = InterpreterOptions();

      // ✅ CARREGAR ArcFace (modelo de reconhecimento facial)
      _interpreter = await Interpreter.fromAsset(
        'assets/models/arcface.tflite', // Modelo ArcFace
        options: options,
      );

      // Verificar shapes
      final inputTensor = _interpreter!.getInputTensors().first;
      final outputTensor = _interpreter!.getOutputTensors().first;

      print('✅ ArcFace carregado!');
      print('📊 Input: ${inputTensor.shape}');
      print('📊 Output: ${outputTensor.shape}');
      print('🎯 Embedding size: $EMBEDDING_SIZE dimensões');

      _modelLoaded = true;

    } catch (e) {
      print('❌ Erro ao carregar ArcFace: $e');
      print('💡 Certifique-se de que o arquivo arcface.tflite está em assets/models/');
      rethrow;
    }
  }

  /// ✅ PRÉ-PROCESSAMENTO OTIMIZADO
  Future<List<double>> extractEmbedding(img.Image image) async {
    if (!_modelLoaded) await init();

    try {
      // 1. Converter para RGB se necessário
      final rgbImage = _ensureRGB(image);

      // 2. Redimensionar para 112x112
      final resized = img.copyResize(rgbImage, width: INPUT_SIZE, height: INPUT_SIZE);

      // 3. Normalização específica do MobileFaceNet
      final input = _preprocessMobileFaceNet(resized);

      // 4. Executar inferência
      final output = List.filled(1 * EMBEDDING_SIZE, 0.0).reshape([1, EMBEDDING_SIZE]);
      _interpreter!.run(input, output);

      // 5. Normalizar embedding
      final embedding = _normalizeEmbedding(output[0]);

      return embedding;

    } catch (e) {
      print('❌ Erro no extractEmbedding: $e');
      rethrow;
    }
  }

  /// ✅ PRÉ-PROCESSAMENTO ESPECÍFICO DO ArcFace
  /// ArcFace normalmente usa normalização [0, 1] ou ImageNet mean/std
  List<List<List<List<float>>>> _preprocessMobileFaceNet(img.Image image) {
    final input = List.generate(
      1, (_) => List.generate(
      3, (c) => List.generate(
      INPUT_SIZE, (y) => List.generate(
      INPUT_SIZE, (x) {
      final pixel = image.getPixel(x, y);

      // MÉTODO 1: Normalização [-1, 1] (MobileFaceNet/ArcFace padrão)
      switch (c) {
        case 0: return (pixel.r / 127.5) - 1.0; // R
        case 1: return (pixel.g / 127.5) - 1.0; // G
        case 2: return (pixel.b / 127.5) - 1.0; // B
        default: return 0.0;
      }

      // MÉTODO 2: Se o método acima não funcionar, tente normalização [0, 1]:
      // switch (c) {
      //   case 0: return pixel.r / 255.0; // R
      //   case 1: return pixel.g / 255.0; // G
      //   case 2: return pixel.b / 255.0; // B
      //   default: return 0.0;
      // }

      // MÉTODO 3: ImageNet mean/std (se os outros não funcionarem):
      // final means = [0.485, 0.456, 0.406];
      // final stds = [0.229, 0.224, 0.225];
      // switch (c) {
      //   case 0: return (pixel.r / 255.0 - means[0]) / stds[0];
      //   case 1: return (pixel.g / 255.0 - means[1]) / stds[1];
      //   case 2: return (pixel.b / 255.0 - means[2]) / stds[2];
      //   default: return 0.0;
      // }
    },
    ),
    ),
    ),
    );

    return input;
  }

  /// ✅ NORMALIZAÇÃO DO EMBEDDING (L2 normalization)
  List<double> _normalizeEmbedding(List<double> embedding) {
    double sum = 0.0;
    for (final value in embedding) {
      sum += value * value;
    }

    final norm = math.sqrt(sum);
    if (norm < 1e-12) {
      throw Exception('Embedding com norma zero');
    }

    return embedding.map((e) => e / norm).toList();
  }

  img.Image _ensureRGB(img.Image image) {
    if (image.numChannels == 3) return image;

    final rgbImage = img.Image(width: image.width, height: image.height, numChannels: 3);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);

        if (image.numChannels == 1) {
          final gray = pixel.r;
          rgbImage.setPixelRgb(x, y, gray, gray, gray);
        } else if (image.numChannels == 4) {
          rgbImage.setPixelRgb(x, y, pixel.r, pixel.g, pixel.b);
        }
      }
    }

    return rgbImage;
  }

  /// ✅ RECONHECIMENTO PRINCIPAL
  Future<Map<String, dynamic>?> recognize(img.Image faceImage) async {
    try {
      print('🔍 Iniciando reconhecimento com ArcFace...');

      final emb = await extractEmbedding(faceImage);
      final known = await DatabaseHelper.instance.getTodosAlunosComFacial();

      if (known.isEmpty) {
        print('📭 Nenhum aluno cadastrado');
        return null;
      }

      double bestScore = 0.0;
      Map<String, dynamic>? bestMatch;

      for (final pessoa in known) {
        final storedEmb = List<double>.from(pessoa['embedding']);
        final score = _cosineSimilarity(emb, storedEmb);

        if (score > bestScore) {
          bestScore = score;
          bestMatch = pessoa;
        }
      }

      print('🎯 Melhor score: ${(bestScore * 100).toStringAsFixed(1)}%');

      if (bestScore >= SIMILARITY_THRESHOLD) {
        print('✅ RECONHECIDO: ${bestMatch!['nome']}');
        // ✅ ADICIONAR o score real ao resultado
        return {
          ...bestMatch,
          'similarity_score': bestScore, // Score real para usar nos logs
        };
      } else {
        print('❌ Não reconhecido (abaixo de ${(SIMILARITY_THRESHOLD * 100).toStringAsFixed(1)}%)');
        return null;
      }

    } catch (e) {
      print('❌ Erro no reconhecimento: $e');
      return null;
    }
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw Exception('Embeddings com tamanhos diferentes');
    }

    double dot = 0.0, normA = 0.0, normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = math.sqrt(normA) * math.sqrt(normB);
    return denominator < 1e-12 ? 0.0 : dot / denominator;
  }

  /// ✅ SALVAR EMBEDDING
  Future<void> saveEmbedding(String cpf, String nome, List<double> embedding) async {
    try {
      await DatabaseHelper.instance.insertEmbedding({
        'cpf': cpf,
        'nome': nome,
        'embedding': embedding,
      });
      print('✅ Embedding salvo para: $nome');
    } catch (e) {
      print('❌ Erro ao salvar embedding: $e');
      rethrow;
    }
  }

  Future<void> saveEmbeddingFromImage(String cpf, String nome, img.Image face) async {
    try {
      final embedding = await extractEmbedding(face);
      await saveEmbedding(cpf, nome, embedding);
    } catch (e) {
      print('❌ Erro ao salvar embedding da imagem: $e');
      rethrow;
    }
  }

  void dispose() {
    _interpreter?.close();
    _modelLoaded = false;
  }
}