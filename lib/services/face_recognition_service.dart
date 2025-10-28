// lib/services/face_recognition_service.dart
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '/database/database_helper.dart';

class FaceRecognitionService {
  static final FaceRecognitionService instance = FaceRecognitionService._internal();
  FaceRecognitionService._internal();

  Interpreter? _interpreter;
  List<int>? _inputShape;
  List<int>? _outputShape;

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

    } catch (e) {
      print("❌ Erro ao carregar modelo: $e");
      rethrow;
    }
  }

  /// Método para diagnosticar o problema
  void diagnoseModel() {
    if (_interpreter == null) {
      print("❌ Modelo não carregado");
      return;
    }

    final inputTensors = _interpreter!.getInputTensors();
    final outputTensors = _interpreter!.getOutputTensors();

    print("🔍 DIAGNÓSTICO DO MODELO:");
    print("📥 Input tensor: ${inputTensors.first}");
    print("📤 Output tensor: ${outputTensors.first}");
    print("🔄 Input shape: ${inputTensors.first.shape}");
    print("🔄 Output shape: ${outputTensors.first.shape}");
  }

  /// Método principal - CHANNELS FIRST [1, 3, 112, 112]
  Future<List<double>> extractEmbedding(img.Image face) async {
    if (_interpreter == null) await loadModel();

    try {
      // Converte para RGB
      final rgbFace = _convertToRGB(face);

      // Redimensiona para 112x112
      final resized = img.copyResize(rgbFace, width: 112, height: 112);

      print("🎯 Usando formato CHANNELS FIRST [1, 3, 112, 112]");

      // Prepara input no formato CHANNELS FIRST
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
      // 1. Melhora a qualidade da imagem
      final enhancedFace = _enhanceImage(face);

      // 2. Converte para RGB garantido
      final rgbFace = _convertToRGB(enhancedFace);

      // 3. Redimensiona
      final resized = img.copyResize(rgbFace, width: 112, height: 112);

      print("🎯 Processamento avançado - Dimensões: ${resized.width}x${resized.height}");

      // 4. Pré-processamento avançado
      final input = _prepareInputEnhanced(resized);
      final output = _prepareOutputTensor();

      _interpreter!.run(input, output);

      final embedding = _processOutputEnhanced(output);

      // Diagnóstico
      diagnoseEmbedding(embedding);

      return embedding;

    } catch (e) {
      print("❌ Erro no extractEmbeddingEnhanced: $e");
      // Fallback para o método básico
      return await extractEmbedding(face);
    }
  }

  /// Melhora a qualidade da imagem para reconhecimento facial
  img.Image _enhanceImage(img.Image image) {
    // Aplica correção de contraste
    final contrasted = img.adjustColor(
      image,
      contrast: 1.1, // Aumenta contraste
    );

    return contrasted;
  }

  /// Pré-processamento básico
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

        // Normalização [0, 1]
        input[0][0][y][x] = pixel.r.toDouble() / 255.0;
        input[0][1][y][x] = pixel.g.toDouble() / 255.0;
        input[0][2][y][x] = pixel.b.toDouble() / 255.0;
      }
    }

    print("🌈 Input preparado: CHANNELS FIRST [0, 1]");
    return input;
  }

  /// Pré-processamento avançado com diferentes esquemas de normalização
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

    // ESQUEMA: Normalização com mean subtraction (comum em modelos ArcFace)
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);

        // Subtrai 127.5 e normaliza para [-1, 1]
        input[0][0][y][x] = (pixel.r.toDouble() - 127.5) / 128.0;
        input[0][1][y][x] = (pixel.g.toDouble() - 127.5) / 128.0;
        input[0][2][y][x] = (pixel.b.toDouble() - 127.5) / 128.0;
      }
    }

    print("🌈 Pré-processamento: Mean Subtraction [-1, 1]");
    return input;
  }

  img.Image _convertToRGB(img.Image image) {
    if (image.numChannels == 3) return image;

    final rgbImage = img.Image(width: image.width, height: image.height, numChannels: 3);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);

        if (image.numChannels == 1) {
          // Grayscale para RGB
          final value = pixel.r;
          rgbImage.setPixelRgb(x, y, value, value, value);
        } else if (image.numChannels == 4) {
          // RGBA para RGB (descarta alpha)
          rgbImage.setPixelRgb(x, y, pixel.r, pixel.g, pixel.b);
        }
      }
    }

    return rgbImage;
  }

  dynamic _prepareOutputTensor() {
    final outputShape = _outputShape!; // [1, 512]

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

  /// Processamento de saída mais robusto
  List<double> _processOutputEnhanced(dynamic output) {
    final outputList = List<double>.from(output[0]);

    // Verifica se o embedding é válido
    if (outputList.any((v) => v.isNaN || v.isInfinite)) {
      throw Exception("Embedding contém valores inválidos");
    }

    // Normalização L2 mais precisa
    final norm = math.sqrt(outputList.fold<double>(0.0, (s, v) => s + v * v));

    if (norm < 1e-8) {
      throw Exception("Embedding com norma muito baixa: $norm");
    }

    final normalized = outputList.map((e) => e / norm).toList();

    // Verifica se a normalização está correta
    final finalNorm = math.sqrt(normalized.fold<double>(0.0, (s, v) => s + v * v));
    print("✅ Embedding normalizado - Norma final: ${finalNorm.toStringAsFixed(10)}");

    return normalized;
  }

  /// Diagnóstico completo do embedding
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

  /// Calcula a média de múltiplos embeddings
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

    // Re-normaliza
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

      // Calcula o embedding médio (mais robusto)
      final averageEmbedding = _calculateAverageEmbedding(allEmbeddings);

      await saveEmbedding(cpf, nome, averageEmbedding);

    } catch (e) {
      print("❌ Erro ao salvar embedding aprimorado: $e");
      rethrow;
    }
  }

  // Métodos de reconhecimento
  Future<Map<String, dynamic>?> recognize(img.Image face) async {
    try {
      final emb = await extractEmbedding(face);
      final known = await DatabaseHelper.instance.getAllEmbeddings();

      if (known.isEmpty) return null;

      double bestScore = 0.0;
      Map<String, dynamic>? bestMatch;

      for (final pessoa in known) {
        final storedEmb = List<double>.from(pessoa['embedding']);
        final score = cosineSimilarity(emb, storedEmb);

        if (score > bestScore) {
          bestScore = score;
          bestMatch = pessoa;
        }
      }

      return bestScore > 0.6 ? bestMatch : null;
    } catch (e) {
      print("❌ Erro no reconhecimento: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> recognizeEnhanced(img.Image face) async {
    try {
      final emb = await extractEmbeddingEnhanced(face);
      final known = await DatabaseHelper.instance.getAllEmbeddings();

      if (known.isEmpty) {
        print("📭 Nenhum embedding salvo no banco de dados");
        return null;
      }

      double bestScore = 0.0;
      Map<String, dynamic>? bestMatch;

      for (final pessoa in known) {
        final storedEmb = List<double>.from(pessoa['embedding']);
        final score = cosineSimilarity(emb, storedEmb);

        print("📊 Comparação com ${pessoa['nome']}: ${score.toStringAsFixed(4)}");

        if (score > bestScore) {
          bestScore = score;
          bestMatch = pessoa;
        }
      }

      print("🎯 MELHOR SCORE: ${bestScore.toStringAsFixed(4)}");

      if (bestScore > 0.75) {
        print("🧠 ✅ Rosto reconhecido com alta confiança: ${bestMatch?['nome']}");
        return bestMatch;
      } else if (bestScore > 0.65) {
        print("⚠️  Rosto possivelmente reconhecido: ${bestMatch?['nome']} (confiança baixa)");
        return bestMatch;
      } else {
        print("🚫 Nenhum rosto correspondente encontrado");
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