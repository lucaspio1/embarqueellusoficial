import 'package:camera/camera.dart';

/// Opções de configuração para a câmera facial unificada
class FaceCameraOptions {
  /// Usar câmera frontal (true) ou traseira (false)
  final bool useFrontCamera;

  /// Título personalizado da tela
  final String? title;

  /// Subtítulo/instrução para o usuário
  final String? subtitle;

  /// Resolução da câmera
  final ResolutionPreset resolution;

  /// Mostrar botão para trocar câmera
  final bool showCameraSwitchButton;

  /// Mostrar contador de capturas (para modo avançado)
  final bool showCaptureCounter;

  /// Delay antes de captura automática (null = sem auto-capture)
  final Duration? autoCapturDelay;

  /// Mostrar overlay de guia facial
  final bool showFaceGuide;

  const FaceCameraOptions({
    this.useFrontCamera = true,
    this.title,
    this.subtitle,
    this.resolution = ResolutionPreset.high,
    this.showCameraSwitchButton = true,
    this.showCaptureCounter = true,
    this.autoCapturDelay,
    this.showFaceGuide = true,
  });

  FaceCameraOptions copyWith({
    bool? useFrontCamera,
    String? title,
    String? subtitle,
    ResolutionPreset? resolution,
    bool? showCameraSwitchButton,
    bool? showCaptureCounter,
    Duration? autoCapturDelay,
    bool? showFaceGuide,
  }) {
    return FaceCameraOptions(
      useFrontCamera: useFrontCamera ?? this.useFrontCamera,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      resolution: resolution ?? this.resolution,
      showCameraSwitchButton: showCameraSwitchButton ?? this.showCameraSwitchButton,
      showCaptureCounter: showCaptureCounter ?? this.showCaptureCounter,
      autoCapturDelay: autoCapturDelay ?? this.autoCapturDelay,
      showFaceGuide: showFaceGuide ?? this.showFaceGuide,
    );
  }
}
