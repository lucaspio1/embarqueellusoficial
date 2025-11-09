# Changelog: Correção Crítica iOS - Sentry + Detecção Facial

**Data:** 2025-11-09
**Versão:** 1.0.6
**Branch:** `claude/fix-facial-detection-ios-011CUxfp7S6e3gpsK46ZLW8F`

---

## 🚨 Problema Reportado

**Descrição:**
- App iOS não realizava detecção facial para gerar embeddings
- Sentry instalado mas NÃO enviava logs/eventos
- Equipe "cega" sem saber o verdadeiro erro
- Contexto: Mac na Amazon (VNC), deploy via TestFlight, sem debug USB

---

## ✅ Correções Implementadas

### 1. **Sentry Nativo iOS** (`ios/Runner/AppDelegate.swift`)

**ANTES:**
```swift
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(...) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(...)
  }
}
```

**DEPOIS:**
```swift
import Sentry

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(...) -> Bool {
    // ✅ Inicializar Sentry NATIVAMENTE
    SentrySDK.start { options in
      options.dsn = "https://..."
      options.debug = true  // Debug forçado
      options.tracesSampleRate = 1.0
      options.enableCaptureFailedRequests = true
      options.enableAutoSessionTracking = true
    }

    SentrySDK.capture(message: "iOS Sentry NATIVO inicializado!")

    GeneratedPluginRegistrant.register(with: self)
    return super.application(...)
  }
}
```

**Motivo:** Sentry NÃO estava sendo inicializado nativamente no iOS, causando perda de eventos/logs.

---

### 2. **Sentry Flutter com Captura Global de Erros** (`lib/main.dart`)

**ANTES:**
```dart
Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = '...';
      options.debug = kDebugMode;  // ❌ PROBLEMA: desliga em Release
      options.environment = kReleaseMode ? 'production' : 'development';
    },
    appRunner: () async {
      // ...
    },
  );
}
```

**DEPOIS:**
```dart
Future<void> main() async {
  // ✅ Capturar TODOS os erros Flutter não tratados
  FlutterError.onError = (details) async {
    await Sentry.captureException(details.exception, stackTrace: details.stack);
  };

  // ✅ Capturar erros assíncronos não tratados
  PlatformDispatcher.instance.onError = (error, stack) {
    Sentry.captureException(error, stackTrace: stack);
    return true;
  };

  await SentryFlutter.init(
    (options) {
      options.dsn = '...';
      options.debug = true;  // ✅ SEMPRE ativo (para diagnóstico)
      options.enableAutoSessionTracking = true;
      options.attachScreenshot = true;  // ✅ Anexar screenshots
      options.attachViewHierarchy = true;  // ✅ Anexar hierarquia
    },
    appRunner: () async {
      await Sentry.captureMessage('App iniciado! Platform: iOS/Android');
      // ...
    },
  );
}
```

**Motivo:**
- `debug = kDebugMode` desligava logs em Release (modo necessário para TestFlight)
- Faltava captura de erros não tratados (Flutter framework + async)
- Faltava anexar screenshots/hierarquia para debug visual

---

### 3. **Logs Detalhados: FaceImageProcessor** (`lib/services/face_image_processor.dart`)

**Adicionado:**
```dart
Future<img.Image> processFile(File file, {int outputSize = 112}) async {
  try {
    debugPrint('[🖼️ FaceImageProcessor] ====== INÍCIO ======');
    debugPrint('[🖼️ FaceImageProcessor] Arquivo: ${file.path}');
    debugPrint('[🖼️ FaceImageProcessor] Plataforma: ${platformDescription}');

    // Verificar se arquivo existe
    if (!await file.exists()) {
      throw Exception('Arquivo não existe: ${file.path}');
    }

    final fileSize = await file.length();
    debugPrint('[🖼️] Tamanho: ${(fileSize / 1024).toStringAsFixed(2)} KB');

    final faces = await _detection.detectFromFile(file);

    if (faces.isEmpty) {
      debugPrint('[❌] NENHUM ROSTO DETECTADO!');
      throw Exception('Nenhum rosto detectado');
    }

    debugPrint('[✅] ${faces.length} rosto(s) detectado(s)');
    // ...

  } catch (e, stackTrace) {
    await Sentry.captureException(e, stackTrace: stackTrace, hint: ...);
    rethrow;
  }
}
```

**Motivo:** Visibilidade completa de cada etapa do processamento de imagem.

---

### 4. **Logs Detalhados: CameraPreviewWidget** (`lib/widgets/camera_preview_widget.dart`)

**Adicionado:**
```dart
Future<void> _tirarFoto() async {
  try {
    print('[📸 CameraPreview] ====== INÍCIO CAPTURA ======');
    print('[📸] Câmera: ${cameras[index].name}');
    print('[📸] Direção: ${cameras[index].lensDirection}');
    print('[📸] Resolução: ${controller.value.previewSize}');

    final image = await controller!.takePicture();

    print('[✅] Foto capturada: ${image.path}');
    print('[📸] ====== CAPTURA CONCLUÍDA ======');

  } catch (e, stackTrace) {
    await Sentry.captureException(e, stackTrace: stackTrace, hint: ...);
    rethrow;
  }
}
```

**Motivo:** Rastrear problemas na captura de foto (permissões, hardware, etc).

---

### 5. **Logs Detalhados: Tela Reconhecimento** (`lib/screens/reconhecimento_facial_completo.dart`)

**Adicionado:**
```dart
Future<void> _iniciarReconhecimento() async {
  try {
    print('[🎯 Reconhecimento] ====== INÍCIO FLUXO ======');

    // Etapa 1: Abrir câmera
    print('[🎯] Etapa 1/3: Abrindo câmera...');
    final imagePath = await _abrirCameraTela(frontal: false);
    print('[✅] Imagem capturada: $imagePath');

    // Etapa 2: Processar imagem
    print('[🎯] Etapa 2/3: Processando imagem...');
    final processedImage = await _processarImagemParaModelo(File(imagePath));
    print('[✅] Imagem processada: ${processedImage.width}x${processedImage.height}');

    // Etapa 3: Reconhecer
    print('[🎯] Etapa 3/3: Comparando com banco...');
    final resultado = await _faceService.recognize(processedImage);
    print('[✅] Comparação concluída');

    // ...
  } catch (e, stackTrace) {
    await Sentry.captureException(e, stackTrace: stackTrace);
    rethrow;
  }
}
```

**Motivo:** Mapear exatamente onde o fluxo de reconhecimento está falhando.

---

## 📊 Arquivos Modificados

### Código:
1. `ios/Runner/AppDelegate.swift` - Inicialização Sentry nativo
2. `lib/main.dart` - Captura global de erros + debug sempre ativo
3. `lib/services/face_image_processor.dart` - Logs detalhados + Sentry
4. `lib/widgets/camera_preview_widget.dart` - Logs de captura + Sentry
5. `lib/screens/reconhecimento_facial_completo.dart` - Logs de fluxo

### Documentação:
6. `IOS_BUILD_INSTRUCTIONS.md` - Guia completo de build/deploy/troubleshooting
7. `CHANGELOG_iOS_Fix.md` - Este arquivo

---

## 🎯 Resultados Esperados

### Antes da Correção:
- ❌ Sentry sem eventos no iOS
- ❌ Sem visibilidade de erros
- ❌ Detecção facial falhando silenciosamente

### Depois da Correção:
- ✅ Sentry recebendo eventos nativos (Swift) + Flutter (Dart)
- ✅ Logs detalhados de CADA etapa do fluxo
- ✅ Screenshots e hierarquia anexados aos erros
- ✅ Captura de erros não tratados (framework + async)
- ✅ Visibilidade completa do que está acontecendo no iPhone

---

## 📱 Como Testar

1. **Build e Deploy:**
   ```bash
   flutter clean
   flutter pub get
   cd ios && pod install --repo-update
   cd .. && flutter build ios --release
   ```

2. **Verificar Sentry:**
   - Acesse: https://sentry.io
   - Procure eventos: `"iOS AppDelegate: Sentry NATIVO inicializado"`
   - Procure eventos: `"App Flutter iniciado! Platform: iOS"`

3. **Testar Detecção Facial:**
   - Abrir app no iPhone (via TestFlight)
   - Ir em "Reconhecimento Facial"
   - Clicar em "RECONHECER POR FOTO"
   - Tirar foto de um rosto
   - Verificar logs no Sentry (aparecem em 30-60 segundos)

---

## 🔍 Logs Esperados no Sentry

**Inicialização:**
```
✅ [iOS Native] Sentry inicializado nativamente no AppDelegate
🔵 [Sentry Flutter] Configurando Sentry...
✅ [Sentry Flutter] Evento de teste enviado!
```

**Fluxo de Reconhecimento (Sucesso):**
```
🎯 [Reconhecimento] Etapa 1/3: Abrindo câmera...
📸 [CameraPreview] Câmera: Back Camera (1920x1080)
✅ [Reconhecimento] Imagem capturada
🎯 [Reconhecimento] Etapa 2/3: Processando imagem...
🖼️ [FaceImageProcessor] Iniciando detecção...
👁️ [FaceDetection] 1 rosto(s) detectado(s)
✅ [Reconhecimento] Imagem processada: 112x112
🎯 [Reconhecimento] Etapa 3/3: Comparando...
✅ RECONHECIDO: João da Silva
```

**Fluxo de Reconhecimento (Falha - Sem Face):**
```
🎯 [Reconhecimento] Etapa 2/3: Processando imagem...
❌ [FaceImageProcessor] NENHUM ROSTO DETECTADO!
👁️ [FaceDetection] Nenhuma face encontrada!
⚠️ Erro: Nenhum rosto detectado na imagem
```

---

## 🚀 Próximos Passos

1. **Testar no TestFlight** - Deploy e verificar Sentry
2. **Analisar eventos no Sentry** - Identificar causa raiz da falha
3. **Ajustar threshold** se necessário (face_recognition_service.dart)
4. **Desabilitar debug** após confirmar funcionamento (produção)

---

## ⚠️ Notas Importantes

- **Debug mode:** Está FORÇADO como `true` para diagnóstico. Desabilitar após confirmar funcionamento.
- **Screenshots:** Sentry anexará screenshots de erros (pode conter dados sensíveis - revisar antes de produção)
- **Logs detalhados:** Podem impactar performance. Remover `debugPrint` excessivos após debug.

---

## 📞 Suporte

**Dashboard Sentry:**
https://o4504103203045376.ingest.us.sentry.io/issues/

**DSN:**
```
https://16c773f79c6fc2a3a4951733ce3570ed@o4504103203045376.ingest.us.sentry.io/4510326779740160
```

---

**Desenvolvido por:** Claude
**Data:** 2025-11-09
**Status:** ✅ PRONTO PARA DEPLOY
