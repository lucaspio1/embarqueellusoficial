import 'dart:math' as math;
import 'dart:ui' show Point;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Serviço de validação de qualidade facial com landmarks e head pose
class FaceValidationService {
  FaceValidationService._();
  static final FaceValidationService instance = FaceValidationService._();

  // Thresholds de validação
  static const double MAX_YAW = 30.0; // ±30° esquerda/direita
  static const double MAX_PITCH = 15.0; // ±15° cima/baixo
  static const double MAX_ROLL = 20.0; // ±20° inclinação
  static const double MIN_EYE_OPEN_PROBABILITY = 0.3; // Anti-spoofing básico
  static const double MIN_FACE_SIZE = 0.15; // 15% da tela
  static const double MAX_FACE_SIZE = 0.85; // 85% da tela

  /// Valida a qualidade de uma face detectada
  FaceValidationResult validate(Face face, int imageWidth, int imageHeight) {
    final errors = <String>[];
    final warnings = <String>[];
    FaceQuality quality = FaceQuality.good;

    // 1. Validar tamanho da face
    final faceSize = _calculateFaceSize(face, imageWidth, imageHeight);
    if (faceSize < MIN_FACE_SIZE) {
      errors.add('Aproxime o rosto da câmera');
      quality = FaceQuality.tooFar;
    } else if (faceSize > MAX_FACE_SIZE) {
      errors.add('Afaste o rosto da câmera');
      quality = FaceQuality.tooClose;
    }

    // 2. Validar head pose (orientação)
    final poseResult = _validateHeadPose(face);
    if (!poseResult.isValid) {
      errors.addAll(poseResult.errors);
      quality = FaceQuality.badPose;
    }

    // 3. Validar landmarks (olhos, nariz, boca)
    final landmarksResult = _validateLandmarks(face);
    if (!landmarksResult.isValid) {
      errors.addAll(landmarksResult.errors);
      if (quality == FaceQuality.good) {
        quality = FaceQuality.missingLandmarks;
      }
    }
    warnings.addAll(landmarksResult.warnings);

    // 4. Anti-spoofing básico (olhos abertos)
    final spoofingResult = _validateLiveness(face);
    if (!spoofingResult.isValid) {
      warnings.addAll(spoofingResult.errors);
    }

    // 5. Validar centralização
    final centerResult = _validateCentering(face, imageWidth, imageHeight);
    if (!centerResult.isValid) {
      warnings.addAll(centerResult.errors);
    }

    final isValid = errors.isEmpty;
    if (isValid && quality == FaceQuality.good && warnings.isEmpty) {
      quality = FaceQuality.excellent;
    }

    return FaceValidationResult(
      isValid: isValid,
      quality: quality,
      errors: errors,
      warnings: warnings,
      confidence: _calculateConfidence(face, faceSize, poseResult, landmarksResult),
      faceSize: faceSize,
    );
  }

  double _calculateFaceSize(Face face, int imageWidth, int imageHeight) {
    final box = face.boundingBox;
    final imageArea = imageWidth * imageHeight;
    final faceArea = box.width * box.height;
    return faceArea / imageArea;
  }

  _ValidationResult _validateHeadPose(Face face) {
    final errors = <String>[];

    final yaw = face.headEulerAngleY ?? 0.0;
    final pitch = face.headEulerAngleX ?? 0.0;
    final roll = face.headEulerAngleZ ?? 0.0;

    if (yaw.abs() > MAX_YAW) {
      if (yaw > 0) {
        errors.add('Vire o rosto mais para a direita');
      } else {
        errors.add('Vire o rosto mais para a esquerda');
      }
    }

    if (pitch.abs() > MAX_PITCH) {
      if (pitch > 0) {
        errors.add('Olhe mais para baixo');
      } else {
        errors.add('Olhe mais para cima');
      }
    }

    if (roll.abs() > MAX_ROLL) {
      errors.add('Mantenha a cabeça reta');
    }

    return _ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }

  _ValidationResult _validateLandmarks(Face face) {
    final errors = <String>[];
    final warnings = <String>[];

    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    final nose = face.landmarks[FaceLandmarkType.noseBase];
    final mouth = face.landmarks[FaceLandmarkType.bottomMouth];

    if (leftEye == null || rightEye == null) {
      errors.add('Mantenha os olhos visíveis');
    }

    if (nose == null) {
      warnings.add('Nariz não detectado claramente');
    }

    if (mouth == null) {
      warnings.add('Boca não detectada claramente');
    }

    // Validar distância entre olhos (muito importante para qualidade)
    if (leftEye != null && rightEye != null) {
      final eyeDistance = _calculateDistance(leftEye.position, rightEye.position);
      if (eyeDistance < 50) {
        warnings.add('Aproxime o rosto');
      }
    }

    return _ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  _ValidationResult _validateLiveness(Face face) {
    final errors = <String>[];

    final leftEyeOpen = face.leftEyeOpenProbability;
    final rightEyeOpen = face.rightEyeOpenProbability;

    if (leftEyeOpen != null && leftEyeOpen < MIN_EYE_OPEN_PROBABILITY) {
      errors.add('Abra o olho esquerdo');
    }

    if (rightEyeOpen != null && rightEyeOpen < MIN_EYE_OPEN_PROBABILITY) {
      errors.add('Abra o olho direito');
    }

    return _ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }

  _ValidationResult _validateCentering(Face face, int imageWidth, int imageHeight) {
    final errors = <String>[];
    final box = face.boundingBox;

    final centerX = box.center.dx;
    final centerY = box.center.dy;

    final imageCenterX = imageWidth / 2;
    final imageCenterY = imageHeight / 2;

    final offsetX = (centerX - imageCenterX).abs() / imageWidth;
    final offsetY = (centerY - imageCenterY).abs() / imageHeight;

    if (offsetX > 0.2) {
      if (centerX < imageCenterX) {
        errors.add('Mova para a direita');
      } else {
        errors.add('Mova para a esquerda');
      }
    }

    if (offsetY > 0.2) {
      if (centerY < imageCenterY) {
        errors.add('Mova para baixo');
      } else {
        errors.add('Mova para cima');
      }
    }

    return _ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }

  double _calculateDistance(Point<int> p1, Point<int> p2) {
    final dx = (p1.x - p2.x).toDouble();
    final dy = (p1.y - p2.y).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }

  double _calculateConfidence(
    Face face,
    double faceSize,
    _ValidationResult poseResult,
    _ValidationResult landmarksResult,
  ) {
    double confidence = 1.0;

    // Penalizar por tamanho inadequado
    if (faceSize < MIN_FACE_SIZE) {
      confidence *= (faceSize / MIN_FACE_SIZE);
    } else if (faceSize > MAX_FACE_SIZE) {
      confidence *= (MAX_FACE_SIZE / faceSize);
    }

    // Penalizar por pose ruim
    final yaw = (face.headEulerAngleY ?? 0.0).abs();
    final pitch = (face.headEulerAngleX ?? 0.0).abs();
    confidence *= math.max(0.0, 1.0 - (yaw / 90.0));
    confidence *= math.max(0.0, 1.0 - (pitch / 90.0));

    // Penalizar por landmarks faltando
    if (!landmarksResult.isValid) {
      confidence *= 0.5;
    }

    return confidence.clamp(0.0, 1.0);
  }
}

/// Resultado da validação de uma face
class FaceValidationResult {
  final bool isValid;
  final FaceQuality quality;
  final List<String> errors;
  final List<String> warnings;
  final double confidence;
  final double faceSize;

  const FaceValidationResult({
    required this.isValid,
    required this.quality,
    required this.errors,
    required this.warnings,
    required this.confidence,
    required this.faceSize,
  });

  String get primaryMessage {
    if (errors.isNotEmpty) return errors.first;
    if (warnings.isNotEmpty) return warnings.first;
    return quality.message;
  }

  bool get isReadyForCapture => isValid && quality.isGoodEnough;
}

enum FaceQuality {
  excellent,
  good,
  tooFar,
  tooClose,
  badPose,
  missingLandmarks,
  poor;

  bool get isGoodEnough => this == FaceQuality.excellent || this == FaceQuality.good;

  String get message {
    switch (this) {
      case FaceQuality.excellent:
        return '✨ Perfeito!';
      case FaceQuality.good:
        return '✅ Boa qualidade';
      case FaceQuality.tooFar:
        return '📏 Aproxime o rosto';
      case FaceQuality.tooClose:
        return '📏 Afaste o rosto';
      case FaceQuality.badPose:
        return '🔄 Ajuste a posição';
      case FaceQuality.missingLandmarks:
        return '👁️ Mantenha rosto visível';
      case FaceQuality.poor:
        return '⚠️ Qualidade baixa';
    }
  }
}

class _ValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  _ValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });
}

/// Resultado de cálculo de alinhamento
class FaceAlignment {
  final double rotationAngle;
  final bool needsAlignment;

  const FaceAlignment({
    required this.rotationAngle,
    required this.needsAlignment,
  });
}
