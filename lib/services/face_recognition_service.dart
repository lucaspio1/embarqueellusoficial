// lib/services/face_recognition_service.dart
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '/database/database_helper.dart';

/// ✅ VERSÃO ATUALIZADA COM:
/// - Limiar de similaridade ajustável (SIMILARITY_THRESHOLD)
/// - Logs detalhados para debug
/// - Busca de TODOS os alunos com facial (não só embarcados)
class FaceRecognitionService {
  static final FaceRecognitionService instance = FaceRecognitionService._internal();
  FaceRecognitionService._internal();

  Interpreter? _interpreter;
  List<int>? _inputShape;
  List<int>? _outputShape;

  // ✅ AJUSTE ESTE VALOR PARA MELHORAR O RECONHECIMENTO
  // 0.5 = Mais flexível (pode reconhecer errado)
  // 0.6 = Balanceado (RECOMENDADO)
  // 0.7 = Mais rígido (pode não reconhecer)
  static const double SIMILARITY_THRESHOLD = 0.6;

  Future<void> init() async {
    if (_interpreter != null) return;
    await loadModel();
  }

  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions();
      _interpreter = await Interpreter.fromAsset(
        'assets/models/arcface.tflite',
        options: options,
      );

      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();

      _inputShape = inputTensors.first.shape;
      _outputShape = outputTensors.first.shape;

      print("✅ Modelo ArcFace carregado com sucesso!");
      print("📊 Input shape: $_inputShape");
      print("📊 Output shape: $_outputShape");
      print("🎯 Limiar de similaridade: ${(SIMILARITY_THRESHOLD * 100).toStringAsFixed(0)}%");

    } catch (e) {
      print("❌ Erro ao carregar modelo: $e");
      rethrow;
    }
  }

  /// Método principal - CHANNELS FIRST [1, 3, 112, 112]
  Future<List<double>> extractEmbedding(img.Image face) async {
    if (_interpreter == null) await loadModel();

    try {
      final rgbFace = _convertToRGB(face);
      final resized = img.copyResize(rgbFace, width: 112, height: 112);

      print("🎯 Usando formato CHANNELS FIRST [1, 3, 112, 112]");

      final input = _prepareInputChannelsFirst(resized);
      final output = _prepareOutputTensor();

      _interpreter!.run(input, output);

      return _processOutput(output);

    } catch (e) {
      print("❌ Erro no extractEmbedding: $e");
      rethrow;
    }
  }

  /// Método aprimorado para maior precisão
  Future<List<double>> extractEmbeddingEnhanced(img.Image face) async {
    if (_interpreter == null) await loadModel();

    try {
      final enhancedFace = _enhanceImage(face);
      final rgbFace = _convertToRGB(enhancedFace);
      final resized = img.copyResize(rgbFace, width: 112, height: 112);

      print("🎯 Processamento avançado - Dimensões: ${resized.width}x${resized.height}");

      final input = _prepareInputEnhanced(resized);
      final output = _prepareOutputTensor();

      _interpreter!.run(input, output);

      final embedding = _processOutputEnhanced(output);

      diagnoseEmbedding(embedding);

      return embedding;

    } catch (e) {
      print("❌ Erro no extractEmbeddingEnhanced: $e");
      return await extractEmbedding(face);
    }
  }

  img.Image _enhanceImage(img.Image image) {
    return img.adjustColor(
      image,
      contrast: 1.1,
    );
  }

  List<List<List<List<double>>>> _prepareInputChannelsFirst(img.Image image) {
    final batchSize = 1;
    final channels = 3;
    final height = image.height;
    final width = image.width;

    final input = List.generate(
      batchSize,
          (_) => List.generate(
        channels,
            (c) => List.generate(
          height,
              (y) => List<double>.filled(width, 0.0),
        ),
      ),
    );

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);

        input[0][0][y][x] = pixel.r.toDouble() / 255.0;
        input[0][1][y][x] = pixel.g.toDouble() / 255.0;
        input[0][2][y][x] = pixel.b.toDouble() / 255.0;
      }
    }

    return input;
  }

  List<List<List<List<double>>>> _prepareInputEnhanced(img.Image image) {
    final batchSize = 1;
    final channels = 3;
    final height = image.height;
    final width = image.width;

    final input = List.generate(
      batchSize,
          (_) => List.generate(
        channels,
            (c) => List.generate(
          height,
              (y) => List<double>.filled(width, 0.0),
        ),
      ),
    );

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);

        input[0][0][y][x] = (pixel.r.toDouble() - 127.5) / 128.0;
        input[0][1][y][x] = (pixel.g.toDouble() - 127.5) / 128.0;
        input[0][2][y][x] = (pixel.b.toDouble() - 127.5) / 128.0;
      }
    }

    return input;
  }

  img.Image _convertToRGB(img.Image image) {
    if (image.numChannels == 3) return image;

    final rgbImage = img.Image(width: image.width, height: image.height, numChannels: 3);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);

        if (image.numChannels == 1) {
          final value = pixel.r;
          rgbImage.setPixelRgb(x, y, value, value, value);
        } else if (image.numChannels == 4) {
          rgbImage.setPixelRgb(x, y, pixel.r, pixel.g, pixel.b);
        }
      }
    }

    return rgbImage;
  }

  dynamic _prepareOutputTensor() {
    final outputShape = _outputShape!;

    return List.generate(
      outputShape[0],
          (i) => List<double>.filled(outputShape[1], 0.0),
    );
  }

  List<double> _processOutput(dynamic output) {
    final outputList = List<double>.from(output[0]);
    final norm = math.sqrt(outputList.fold<double>(0.0, (s, v) => s + v * v));

    if (norm == 0.0) {
      throw Exception("Embedding com norma zero");
    }

    return outputList.map((e) => e / norm).toList();
  }

  List<double> _processOutputEnhanced(dynamic output) {
    final outputList = List<double>.from(output[0]);

    if (outputList.any((v) => v.isNaN || v.isInfinite)) {
      throw Exception("Embedding contém valores inválidos");
    }

    final norm = math.sqrt(outputList.fold<double>(0.0, (s, v) => s + v * v));

    if (norm < 1e-8) {
      throw Exception("Embedding com norma muito baixa: $norm");
    }

    final normalized = outputList.map((e) => e / norm).toList();

    final finalNorm = math.sqrt(normalized.fold<double>(0.0, (s, v) => s + v * v));
    print("✅ Embedding normalizado - Norma final: ${finalNorm.toStringAsFixed(10)}");

    return normalized;
  }

  void diagnoseEmbedding(List<double> embedding) {
    final minVal = embedding.reduce((a, b) => a < b ? a : b);
    final maxVal = embedding.reduce((a, b) => a > b ? a : b);
    final mean = embedding.reduce((a, b) => a + b) / embedding.length;
    final norm = math.sqrt(embedding.fold<double>(0.0, (s, v) => s + v * v));

    print("🔍 DIAGNÓSTICO DO EMBEDDING:");
    print("📊 Dimensão: ${embedding.length}");
    print("📊 Norma L2: ${norm.toStringAsFixed(6)}");
    print("📊 Valores - Min: ${minVal.toStringAsFixed(6)}, Max: ${maxVal.toStringAsFixed(6)}, Média: ${mean.toStringAsFixed(6)}");
  }

  List<double> _calculateAverageEmbedding(List<List<double>> embeddings) {
    if (embeddings.isEmpty) throw Exception("Nenhum embedding para calcular média");

    final length = embeddings.first.length;
    final average = List<double>.filled(length, 0.0);

    for (final embedding in embeddings) {
      for (int i = 0; i < length; i++) {
        average[i] += embedding[i];
      }
    }

    for (int i = 0; i < length; i++) {
      average[i] /= embeddings.length;
    }

    final norm = math.sqrt(average.fold<double>(0.0, (s, v) => s + v * v));
    return average.map((e) => e / norm).toList();
  }

  Future<void> saveEmbeddingEnhanced(String cpf, String nome, List<img.Image> faces) async {
    try {
      print("💾 Salvando embedding aprimorado para: $nome");
      print("📸 Processando ${faces.length} imagens...");

      List<List<double>> allEmbeddings = [];

      for (int i = 0; i < faces.length; i++) {
        print("🖼️ Processando imagem ${i + 1}/${faces.length}");
        final embedding = await extractEmbeddingEnhanced(faces[i]);
        allEmbeddings.add(embedding);
      }

      final averageEmbedding = _calculateAverageEmbedding(allEmbeddings);

      await saveEmbedding(cpf, nome, averageEmbedding);

    } catch (e) {
      print("❌ Erro ao salvar embedding aprimorado: $e");
      rethrow;
    }
  }

  // =========================================================================
  // ✅ MÉTODOS DE RECONHECIMENTO ATUALIZADOS
  // =========================================================================

  /// ✅ RECONHECIMENTO COM LIMIAR AJUSTÁVEL E LOGS DETALHADOS
  Future<Map<String, dynamic>?> recognize(img.Image face) async {
    try {
      final emb = await extractEmbedding(face);

      // ✅ BUSCAR TODOS OS ALUNOS COM FACIAL (não só embarcados)
      final known = await DatabaseHelper.instance.getTodosAlunosComFacial();

      if (known.isEmpty) {
        print("📭 [Reconhecimento] Nenhum aluno com facial cadastrada");
        return null;
      }

      print('🔍 ===== INICIANDO RECONHECIMENTO =====');
      print('🔍 Total de alunos para comparar: ${known.length}');
      print('🔍 Limiar configurado: ${(SIMILARITY_THRESHOLD * 100).toStringAsFixed(1)}%');
      print('');

      double bestScore = 0.0;
      Map<String, dynamic>? bestMatch;

      for (final pessoa in known) {
        final storedEmb = List<double>.from(pessoa['embedding']);
        final score = cosineSimilarity(emb, storedEmb);

        // ✅ LOG DETALHADO DE CADA COMPARAÇÃO
        print('  ${pessoa['nome']}: ${(score * 100).toStringAsFixed(1)}%');

        if (score > bestScore) {
          bestScore = score;
          bestMatch = pessoa;
        }
      }

      print('');
      print('🔍 ================================');
      print('🔍 Melhor match: ${bestMatch?['nome']}');
      print('🔍 Similaridade: ${(bestScore * 100).toStringAsFixed(1)}%');
      print('🔍 ================================');

      // ✅ USAR LIMIAR CONFIGURÁVEL
      if (bestScore >= SIMILARITY_THRESHOLD) {
        print('✅ RECONHECIDO!');
        return bestMatch;
      } else {
        print('❌ NÃO RECONHECIDO (abaixo do limiar)');
        print('💡 Dica: Se deveria ter reconhecido, diminua SIMILARITY_THRESHOLD');
        print('💡 Dica: Se está reconhecendo errado, aumente SIMILARITY_THRESHOLD');
        return null;
      }
    } catch (e) {
      print("❌ Erro no reconhecimento: $e");
      return null;
    }
  }

  /// ✅ RECONHECIMENTO APRIMORADO COM LIMIAR AJUSTÁVEL
  Future<Map<String, dynamic>?> recognizeEnhanced(img.Image face) async {
    try {
      final emb = await extractEmbeddingEnhanced(face);

      // ✅ BUSCAR TODOS OS ALUNOS COM FACIAL
      final known = await DatabaseHelper.instance.getTodosAlunosComFacial();

      if (known.isEmpty) {
        print("📭 [ReconhecimentoEnhanced] Nenhum aluno com facial cadastrada");
        return null;
      }

      print('🔍 ===== RECONHECIMENTO APRIMORADO =====');
      print('🔍 Total de alunos: ${known.length}');
      print('🔍 Limiar: ${(SIMILARITY_THRESHOLD * 100).toStringAsFixed(1)}%');
      print('');

      double bestScore = 0.0;
      Map<String, dynamic>? bestMatch;

      for (final pessoa in known) {
        final storedEmb = List<double>.from(pessoa['embedding']);
        final score = cosineSimilarity(emb, storedEmb);

        print("📊 Comparação com ${pessoa['nome']}: ${(score * 100).toStringAsFixed(1)}%");

        if (score > bestScore) {
          bestScore = score;
          bestMatch = pessoa;
        }
      }

      print('');
      print("🎯 MELHOR SCORE: ${(bestScore * 100).toStringAsFixed(1)}%");

      if (bestScore >= SIMILARITY_THRESHOLD) {
        print("✅ Reconhecido: ${bestMatch?['nome']}");
        return bestMatch;
      } else {
        print("❌ Não reconhecido (score abaixo de ${(SIMILARITY_THRESHOLD * 100).toStringAsFixed(1)}%)");

        // Sugestões baseadas no score
        if (bestScore > SIMILARITY_THRESHOLD - 0.1) {
          print("⚠️ QUASE! O score foi ${(bestScore * 100).toStringAsFixed(1)}%");
          print("💡 Considere diminuir o limiar para ${((bestScore - 0.05) * 100).toStringAsFixed(1)}%");
        }

        return null;
      }
    } catch (e) {
      print("❌ Erro no reconhecimento aprimorado: $e");
      return null;
    }
  }

  double cosineSimilarity(List<double> e1, List<double> e2) {
    if (e1.length != e2.length) {
      throw Exception("Embeddings com tamanhos diferentes: ${e1.length} vs ${e2.length}");
    }

    double dot = 0.0, norm1 = 0.0, norm2 = 0.0;
    for (int i = 0; i < e1.length; i++) {
      dot += e1[i] * e2[i];
      norm1 += e1[i] * e1[i];
      norm2 += e2[i] * e2[i];
    }

    final denominator = math.sqrt(norm1) * math.sqrt(norm2);
    return denominator == 0.0 ? 0.0 : dot / denominator;
  }

  Future<void> saveEmbedding(String cpf, String nome, List<double> embedding) async {
    try {
      await DatabaseHelper.instance.insertEmbedding({
        'cpf': cpf,
        'nome': nome,
        'embedding': embedding,
      });
      print("✅ Embedding salvo para: $nome");
    } catch (e) {
      print("❌ Erro ao salvar embedding: $e");
      rethrow;
    }
  }

  Future<void> saveEmbeddingFromImage(String cpf, String nome, img.Image face) async {
    try {
      final embedding = await extractEmbeddingEnhanced(face);
      await saveEmbedding(cpf, nome, embedding);
    } catch (e) {
      print("❌ Erro ao salvar embedding da imagem: $e");
      rethrow;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}