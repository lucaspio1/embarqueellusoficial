/// Modos de operação da câmera facial unificada
enum CameraMode {
  /// Cadastro facial simples (1 foto)
  enrollment,

  /// Cadastro facial avançado (3 fotos para melhor precisão)
  enrollmentAdvanced,

  /// Reconhecimento facial
  recognition,
}

extension CameraModeExtension on CameraMode {
  /// Título padrão para cada modo
  String get defaultTitle {
    switch (this) {
      case CameraMode.enrollment:
        return 'Cadastrar Facial';
      case CameraMode.enrollmentAdvanced:
        return 'Cadastro Avançado';
      case CameraMode.recognition:
        return 'Reconhecer Aluno';
    }
  }

  /// Ícone sugerido para cada modo
  String get icon {
    switch (this) {
      case CameraMode.enrollment:
        return '📸';
      case CameraMode.enrollmentAdvanced:
        return '📷';
      case CameraMode.recognition:
        return '🔍';
    }
  }

  /// Se deve fazer múltiplas capturas
  bool get isMultiCapture {
    return this == CameraMode.enrollmentAdvanced;
  }

  /// Número de fotos a capturar
  int get captureCount {
    switch (this) {
      case CameraMode.enrollment:
      case CameraMode.recognition:
        return 1;
      case CameraMode.enrollmentAdvanced:
        return 3;
    }
  }
}
