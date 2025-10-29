// lib/services/face_recognition_service.dart - COMPLETAMENTE REFEITO (CORRIGIDO)
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:embarqueellus/database/database_helper.dart';

/// Serviço de Reconhecimento Facial com ArcFace
class FaceRecognitionService {
  static final FaceRecognitionService instance = FaceRecognitionService._internal();
  FaceRecognitionService._internal();

  Interpreter? _interpreter;
  bool _modelLoaded = false;

  // Configurações
  static const double SIMILARITY_THRESHOLD = 0.6; // ajuste conforme calibração
  static const int INPUT_SIZE = 112;              // ArcFace usa 112x112
  static const int EMBEDDING_SIZE = 512;          // ArcFace retorna 512 dims

  Future<void> init() async {
    if (_modelLoaded) return;
    await _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      print('🧠 Carregando modelo ArcFace...');
      final options = InterpreterOptions();

      _interpreter = await Interpreter.fromAsset(
        'assets/models/arcface.tflite',
        options: options,
      );

      final inputTensor = _interpreter!.getInputTensors().first;
      final outputTensor = _interpreter!.getOutputTensors().first;

      print('✅ ArcFace carregado!');
      print('📊 Input: ${inputTensor.shape}');
      print('📊 Output: ${outputTensor.shape}');
      print('🎯 Embedding size: $EMBEDDING_SIZE');
      _modelLoaded = true;
    } catch (e) {
      print('❌ Erro ao carregar ArcFace: $e');
      rethrow;
    }
  }

  /// Extrai embedding (512D) normalizado (L2)
  Future<List<double>> extractEmbedding(img.Image image) async {
    if (!_modelLoaded) await init();
    try {
      final rgb = _ensureRGB(image);
      final resized = img.copyResize(rgb, width: INPUT_SIZE, height: INPUT_SIZE);
      final input = _preprocessArcFace(resized);

      final output = List.filled(EMBEDDING_SIZE, 0.0).reshape([1, EMBEDDING_SIZE]);
      _interpreter!.run(input, output);

      final embedding = _normalizeL2(output[0]);
      return embedding;
    } catch (e) {
      print('❌ Erro no extractEmbedding: $e');
      rethrow;
    }
  }

  /// Pré-processamento ArcFace – NCHW [1,3,112,112], valores [0..1]
  List<List<List<List<double>>>> _preprocessArcFace(img.Image image) {
    return List.generate(
      1,
          (_) => List.generate(
        3,
            (c) => List.generate(
          INPUT_SIZE,
              (y) => List.generate(
            INPUT_SIZE,
                (x) {
              final p = image.getPixel(x, y);
              switch (c) {
                case 0:
                  return p.r / 255.0; // R
                case 1:
                  return p.g / 255.0; // G
                case 2:
                  return p.b / 255.0; // B
                default:
                  return 0.0;
              }
            },
          ),
        ),
      ),
    );
  }

  List<double> _normalizeL2(List<double> v) {
    double sum = 0.0;
    for (final x in v) sum += x * x;
    final norm = math.sqrt(sum);
    if (norm < 1e-12) throw Exception('Embedding com norma zero');
    return v.map((e) => e / norm).toList();
  }

  img.Image _ensureRGB(img.Image image) {
    if (image.numChannels == 3) return image;
    final rgb = img.Image(width: image.width, height: image.height, numChannels: 3);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        if (image.numChannels == 1) {
          final g = p.r;
          rgb.setPixelRgb(x, y, g, g, g);
        } else if (image.numChannels == 4) {
          rgb.setPixelRgb(x, y, p.r, p.g, p.b);
        }
      }
    }
    return rgb;
  }

  /// Reconhecimento principal – consulta embeddings do SQLite
  Future<Map<String, dynamic>?> recognize(img.Image faceImage) async {
    try {
      print('🔍 Iniciando reconhecimento com ArcFace...');
      final probe = await extractEmbedding(faceImage);

      final known = await DatabaseHelper.instance.getTodosAlunosComFacial();
      if (known.isEmpty) {
        print('📭 Nenhum aluno com facial cadastrada');
        return null;
      }

      double bestScore = 0.0;
      Map<String, dynamic>? best;

      for (final pessoa in known) {
        final stored = List<double>.from(pessoa['embedding']);
        final score = _cosineSimilarity(probe, stored);
        if (score > bestScore) {
          bestScore = score;
          best = pessoa;
        }
      }

      print('🎯 Melhor score: ${(bestScore * 100).toStringAsFixed(1)}%');

      if (bestScore >= SIMILARITY_THRESHOLD && best != null) {
        print('✅ RECONHECIDO: ${best['nome']}');
        return {
          ...best,
          'similarity_score': bestScore,
        };
      }
      print('❌ Não reconhecido (abaixo de ${(SIMILARITY_THRESHOLD * 100).toStringAsFixed(1)}%)');
      return null;
    } catch (e) {
      print('❌ Erro no reconhecimento: $e');
      return null;
    }
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) throw Exception('Embeddings com tamanhos diferentes');
    double dot = 0.0, na = 0.0, nb = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    final den = math.sqrt(na) * math.sqrt(nb);
    return den < 1e-12 ? 0.0 : dot / den;
  }

  /// Salva embedding no SQLite (tabela embeddings)
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
    final emb = await extractEmbedding(face);
    await saveEmbedding(cpf, nome, emb);
  }

  Future<void> saveEmbeddingEnhanced(String cpf, String nome, List<img.Image> faces) async {
    if (faces.isEmpty) throw Exception('Nenhuma imagem fornecida');
    print('📸 Processando ${faces.length} imagens para embedding avançado...');

    final acc = List<double>.filled(EMBEDDING_SIZE, 0.0);
    for (int i = 0; i < faces.length; i++) {
      print('   -> Imagem ${i + 1}/${faces.length}');
      final emb = await extractEmbedding(faces[i]);
      for (int j = 0; j < EMBEDDING_SIZE; j++) {
        acc[j] += emb[j];
      }
    }
    for (int j = 0; j < EMBEDDING_SIZE; j++) {
      acc[j] /= faces.length;
    }
    final normalized = _normalizeL2(acc);
    await saveEmbedding(cpf, nome, normalized);
    print('✅ Embedding avançado salvo');
  }

  void dispose() {
    _interpreter?.close();
    _modelLoaded = false;
  }
}
