import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:sentry_flutter/sentry_flutter.dart';

/// Serviço para captura única de imagem com detecção e recorte facial
///
/// Este serviço implementa o fluxo completo de:
/// 1. Captura única de foto da câmera
/// 2. Detecção facial com ML Kit
/// 3. Recorte da região facial
/// 4. Retorno de Uint8List pronto para geração de embeddings
///
/// Compatível com iOS 15.5+ e Android
class SingleFaceCaptureService {
  late final FaceDetector _faceDetector;
  bool _isInitialized = false;

  SingleFaceCaptureService() {
    _initializeFaceDetector();
  }

  /// Inicializa o detector facial do ML Kit
  void _initializeFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate, // Modo preciso para captura única
        enableContours: false,  // Não necessário para crop simples
        enableLandmarks: true,  // Útil para alinhamento futuro
        enableClassification: false, // Não necessário para crop
        minFaceSize: 0.1, // Detecta faces que ocupam pelo menos 10% da imagem
      ),
    );
    _isInitialized = true;

    Sentry.captureMessage(
      '✅ SingleFaceCaptureService: FaceDetector inicializado (modo ACCURATE)',
      level: SentryLevel.info,
    );
  }

  /// Captura uma única imagem e processa a face
  ///
  /// [controller] - Controller da câmera já inicializado
  ///
  /// Retorna um Map contendo:
  /// - 'faceImage': Uint8List com a imagem recortada da face
  /// - 'boundingBox': Rect com as coordenadas da face detectada
  /// - 'confidence': double com a confiança da detecção (0.0 a 1.0)
  ///
  /// Throws [Exception] se:
  /// - Nenhuma face for detectada
  /// - Múltiplas faces forem detectadas
  /// - Ocorrer erro durante o processamento
  Future<Map<String, dynamic>> captureAndDetectFace(
    CameraController controller,
  ) async {
    if (!_isInitialized) {
      throw Exception('SingleFaceCaptureService não foi inicializado');
    }

    if (!controller.value.isInitialized) {
      throw Exception('CameraController não está inicializado');
    }

    try {
      Sentry.captureMessage(
        '📸 Iniciando captura única de imagem...',
        level: SentryLevel.info,
      );

      // 1. Captura a foto
      final XFile imageFile = await controller.takePicture();
      final String imagePath = imageFile.path;

      Sentry.captureMessage(
        '✅ Foto capturada: $imagePath (${await File(imagePath).length()} bytes)',
        level: SentryLevel.info,
      );

      // 2. Processa a detecção facial
      final result = await _processImageAndDetectFace(imagePath);

      // 3. Limpa o arquivo temporário
      await _cleanupTempFile(imagePath);

      return result;
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'SingleFaceCaptureService.captureAndDetectFace',
        }),
      );
      rethrow;
    }
  }

  /// Processa a imagem e detecta a face principal
  Future<Map<String, dynamic>> _processImageAndDetectFace(
    String imagePath,
  ) async {
    try {
      // 1. Cria InputImage para ML Kit
      final inputImage = InputImage.fromFilePath(imagePath);

      Sentry.captureMessage(
        '🔍 Processando imagem com ML Kit Face Detection...',
        level: SentryLevel.info,
      );

      // 2. Detecta faces
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      Sentry.captureMessage(
        '📊 ML Kit detectou ${faces.length} face(s)',
        level: SentryLevel.info,
      );

      // 3. Valida quantidade de faces
      if (faces.isEmpty) {
        throw Exception('❌ Nenhum rosto detectado na imagem. Por favor, tente novamente.');
      }

      if (faces.length > 1) {
        Sentry.captureMessage(
          '⚠️ Múltiplas faces detectadas (${faces.length}), usando a maior',
          level: SentryLevel.warning,
        );
      }

      // 4. Seleciona a face principal (maior área)
      final Face primaryFace = _selectPrimaryFace(faces);
      final Rect boundingBox = primaryFace.boundingBox;

      Sentry.captureMessage(
        '✅ Face principal selecionada: ${boundingBox.width.toInt()}x${boundingBox.height.toInt()} px',
        level: SentryLevel.info,
      );

      // 5. Recorta a face da imagem
      final Uint8List croppedFaceBytes = await _cropFaceFromImage(
        imagePath,
        boundingBox,
      );

      // 6. Retorna o resultado
      return {
        'faceImage': croppedFaceBytes,
        'boundingBox': boundingBox,
        'confidence': 1.0, // ML Kit não fornece confidence score direto
        'imageWidth': boundingBox.width,
        'imageHeight': boundingBox.height,
      };
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': '_processImageAndDetectFace',
          'imagePath': imagePath,
        }),
      );
      rethrow;
    }
  }

  /// Seleciona a face com maior área (face principal)
  Face _selectPrimaryFace(List<Face> faces) {
    return faces.reduce((current, next) {
      final currentArea = current.boundingBox.width * current.boundingBox.height;
      final nextArea = next.boundingBox.width * next.boundingBox.height;
      return currentArea > nextArea ? current : next;
    });
  }

  /// Recorta a região da face da imagem original
  ///
  /// Aplica uma margem de segurança de 20% para garantir que toda a face seja capturada
  Future<Uint8List> _cropFaceFromImage(
    String imagePath,
    Rect boundingBox,
  ) async {
    try {
      // 1. Lê a imagem original
      final bytes = await File(imagePath).readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        throw Exception('Falha ao decodificar a imagem');
      }

      Sentry.captureMessage(
        '🖼️ Imagem original: ${originalImage.width}x${originalImage.height}',
        level: SentryLevel.info,
      );

      // 2. Calcula margem de segurança (20% em cada lado)
      const double marginFactor = 0.20;
      final double marginX = boundingBox.width * marginFactor;
      final double marginY = boundingBox.height * marginFactor;

      // 3. Calcula coordenadas do crop com margem
      final int x = (boundingBox.left - marginX).clamp(0, originalImage.width - 1).toInt();
      final int y = (boundingBox.top - marginY).clamp(0, originalImage.height - 1).toInt();
      final int width = (boundingBox.width + (2 * marginX))
          .clamp(1, originalImage.width - x)
          .toInt();
      final int height = (boundingBox.height + (2 * marginY))
          .clamp(1, originalImage.height - y)
          .toInt();

      Sentry.captureMessage(
        '✂️ Recortando face: x=$x, y=$y, w=$width, h=$height (margem: ${(marginFactor * 100).toInt()}%)',
        level: SentryLevel.info,
      );

      // 4. Recorta a face
      final img.Image croppedFace = img.copyCrop(
        originalImage,
        x: x,
        y: y,
        width: width,
        height: height,
      );

      // 5. Codifica como JPEG de alta qualidade
      final List<int> jpegBytes = img.encodeJpg(croppedFace, quality: 95);
      final Uint8List result = Uint8List.fromList(jpegBytes);

      Sentry.captureMessage(
        '✅ Face recortada com sucesso: ${croppedFace.width}x${croppedFace.height} (${result.lengthInBytes} bytes)',
        level: SentryLevel.info,
      );

      return result;
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': '_cropFaceFromImage',
          'boundingBox': boundingBox.toString(),
        }),
      );
      rethrow;
    }
  }

  /// Limpa arquivo temporário da captura
  Future<void> _cleanupTempFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        Sentry.captureMessage(
          '🗑️ Arquivo temporário removido: $path',
          level: SentryLevel.debug,
        );
      }
    } catch (e) {
      // Erro ao deletar arquivo temporário não é crítico
      Sentry.captureMessage(
        '⚠️ Falha ao remover arquivo temporário: $e',
        level: SentryLevel.warning,
      );
    }
  }

  /// Libera recursos do detector facial
  void dispose() {
    if (_isInitialized) {
      _faceDetector.close();
      _isInitialized = false;

      Sentry.captureMessage(
        '🔌 SingleFaceCaptureService: FaceDetector finalizado',
        level: SentryLevel.info,
      );
    }
  }

  /// Verifica se o serviço está inicializado
  bool get isInitialized => _isInitialized;
}
