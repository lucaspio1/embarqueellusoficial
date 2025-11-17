// lib/services/face_recognition_service.dart - COMPLETAMENTE REFEITO (CORRIGIDO)
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:embarqueellus/database/database_helper.dart';

/// Serviço de Reconhecimento Facial com ArcFace
class FaceRecognitionService {
  static final FaceRecognitionService instance = FaceRecognitionService._internal();
  FaceRecognitionService._internal();

  Interpreter? _interpreter;
  bool _modelLoaded = false;

  // Configurações
  static const double DISTANCE_THRESHOLD = 1.1; // ajuste conforme calibração
  static const int INPUT_SIZE = 112;              // ArcFace usa 112x112
  static const int EMBEDDING_SIZE = 512;          // ArcFace retorna 512 dims

  Future<void> init() async {
    if (_modelLoaded) return;
    await _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final options = InterpreterOptions();

      _interpreter = await Interpreter.fromAsset(
        'assets/models/arcface.tflite',
        options: options,
      );

      _modelLoaded = true;
    } catch (e) {
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
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao extrair embedding facial',
          'image_width': image.width,
          'image_height': image.height,
          'image_channels': image.numChannels,
        }),
      );
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
      final probe = await extractEmbedding(faceImage);

      // ✅ FILTRO DE DATA: Buscar apenas alunos com viagem ativa
      final known = await DatabaseHelper.instance.getTodosAlunosComFacialAtivos();
      if (known.isEmpty) {
        await Sentry.captureMessage(
          'Tentativa de reconhecimento facial sem alunos ativos',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('facial_error_type', 'no_active_students');
            scope.setContexts('info', {
              'total_students': 0,
              'message': 'Nenhum aluno com facial ativa (dentro do período de viagem)',
            });
          },
        );
        return null;
      }

      double bestDistance = double.infinity;
      Map<String, dynamic>? best;

      for (final pessoa in known) {
        final stored = _toDoubleList(pessoa['embedding']);
        final distance = _euclideanDistance(probe, stored);
        if (distance < bestDistance) {
          bestDistance = distance;
          best = pessoa;
        }
      }

      final double confidence =
          (DISTANCE_THRESHOLD - bestDistance) / DISTANCE_THRESHOLD;
      final double normalizedConfidence = confidence.clamp(0.0, 1.0);

      if (bestDistance <= DISTANCE_THRESHOLD && best != null) {
        await Sentry.captureMessage(
          'Reconhecimento facial bem-sucedido',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setTag('facial_result', 'success');
            scope.setContexts('recognition', {
              'student_name': best!['nome'],
              'student_cpf': best['cpf'],
              'distance_l2': bestDistance,
              'confidence': normalizedConfidence,
              'threshold': DISTANCE_THRESHOLD,
              'total_students_checked': known.length,
            });
          },
        );
        return {
          ...best,
          'similarity_score': normalizedConfidence,
          'distance_l2': bestDistance,
        };
      }

      await Sentry.captureMessage(
        'Facial não encontrada - Nenhum aluno reconhecido',
        level: SentryLevel.warning,
        withScope: (scope) {
          scope.setTag('facial_error_type', 'face_not_recognized');
          scope.setContexts('recognition_attempt', {
            'best_distance': bestDistance,
            'threshold': DISTANCE_THRESHOLD,
            'distance_difference': bestDistance - DISTANCE_THRESHOLD,
            'total_students_checked': known.length,
            'best_match_name': best?['nome'] ?? 'N/A',
            'best_match_cpf': best?['cpf'] ?? 'N/A',
          });
        },
      );
      return null;
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro crítico no processo de reconhecimento facial',
        }),
      );
      return null;
    }
  }

  double _euclideanDistance(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw Exception('Embeddings com tamanhos diferentes');
    }
    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      final double diff = a[i] - b[i];
      sum += diff * diff;
    }
    return math.sqrt(sum);
  }

  List<double> _toDoubleList(dynamic raw) {
    if (raw is List<double>) return raw;
    if (raw is List) {
      return raw.map((e) => (e as num).toDouble()).toList();
    }
    throw Exception('Embedding em formato inválido: ${raw.runtimeType}');
  }

  /// Salva embedding no SQLite (tabela embeddings)
  Future<void> saveEmbedding(String cpf, String nome, List<double> embedding) async {
    try {
      await DatabaseHelper.instance.insertEmbedding({
        'cpf': cpf,
        'nome': nome,
        'embedding': embedding,
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> saveEmbeddingFromImage(String cpf, String nome, img.Image face) async {
    final emb = await extractEmbedding(face);
    await saveEmbedding(cpf, nome, emb);
  }

  Future<void> saveEmbeddingEnhanced(String cpf, String nome, List<img.Image> faces) async {
    if (faces.isEmpty) throw Exception('Nenhuma imagem fornecida');

    final acc = List<double>.filled(EMBEDDING_SIZE, 0.0);
    for (int i = 0; i < faces.length; i++) {
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
  }

  void dispose() {
    _interpreter?.close();
    _modelLoaded = false;
  }
}
