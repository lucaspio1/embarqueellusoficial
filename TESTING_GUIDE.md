# Guia de Testes - Reconhecimento Facial

## 🧪 Pré-requisitos

Antes de iniciar os testes, execute os seguintes comandos:

```bash
# 1. Instalar dependências atualizadas
flutter pub get

# 2. Atualizar pods do iOS (se estiver usando macOS)
cd ios
pod repo update
pod install
cd ..

# 3. Limpar build anterior
flutter clean
flutter pub get
```

---

## ✅ Testes de Compilação

### 1. Verificar Análise Estática

```bash
flutter analyze
```

**Esperado**: Nenhum erro, apenas warnings aceitáveis.

---

### 2. Compilar para iOS (macOS apenas)

```bash
flutter build ios --debug --no-codesign
```

**Esperado**: Build concluído sem erros.

---

### 3. Compilar para Android

```bash
flutter build apk --debug
```

**Esperado**: APK gerado em `build/app/outputs/flutter-apk/app-debug.apk`

---

## 📱 Testes em Dispositivo Real

### Teste 1: Inicialização da Câmera

#### Código de Teste:
```dart
import 'package:embarqueellus/services/face_capture_service.dart';

void testCameraInit() async {
  final service = FaceCaptureService.instance;

  try {
    await service.initCamera(useFrontCamera: false);
    print('✅ Câmera inicializada com sucesso');
    print('Controller: ${service.controller}');
    print('Initialized: ${service.isInitialized}');
  } catch (e) {
    print('❌ Erro ao inicializar câmera: $e');
  }
}
```

**Checklist**:
- [ ] Câmera inicializa sem erros
- [ ] Controller não é null
- [ ] isInitialized retorna true
- [ ] Preview da câmera é exibido

---

### Teste 2: Captura de Foto Simples

#### Código de Teste:
```dart
void testPhotoCapture() async {
  final service = FaceCaptureService.instance;

  try {
    await service.initCamera();

    // Aguardar estabilização
    await Future.delayed(Duration(seconds: 2));

    final result = await service.captureAndDetectFace();

    print('✅ Face capturada!');
    print('Bytes: ${result.croppedFaceBytes.length}');
    print('BBox: ${result.boundingBox.width}x${result.boundingBox.height}');
    print('Path: ${result.imagePath}');

    assert(result.croppedFaceBytes.isNotEmpty, 'Bytes não podem ser vazios');
    assert(result.boundingBox.width > 0, 'BBox width deve ser > 0');

    print('✅ Todos os asserts passaram!');
  } catch (e) {
    print('❌ Erro: $e');
  }
}
```

**Checklist**:
- [ ] Foto é capturada sem erros
- [ ] Face é detectada (se houver rosto na frente)
- [ ] croppedFaceBytes não está vazio
- [ ] boundingBox tem dimensões válidas
- [ ] imagePath existe no sistema de arquivos

---

### Teste 3: Detecção Facial com ML Kit

#### Código de Teste:
```dart
import 'dart:io';
import 'package:embarqueellus/services/face_detection_service.dart';

void testFaceDetection(String imagePath) async {
  final service = FaceDetectionService.instance;

  try {
    final faces = await service.detectFromPath(imagePath);

    print('Faces detectadas: ${faces.length}');

    for (var i = 0; i < faces.length; i++) {
      final face = faces[i];
      print('Face $i:');
      print('  BBox: ${face.boundingBox.width}x${face.boundingBox.height}');
      print('  Left: ${face.boundingBox.left}');
      print('  Top: ${face.boundingBox.top}');
    }

    assert(faces.isNotEmpty, 'Deve detectar ao menos 1 face');
    print('✅ Detecção funcionando!');
  } catch (e) {
    print('❌ Erro: $e');
  }
}
```

**Checklist**:
- [ ] Detecta faces em fotos de teste
- [ ] Bounding boxes são precisos
- [ ] Não detecta falsas faces
- [ ] Performance aceitável (<1s)

---

### Teste 4: Processamento e Recorte

#### Código de Teste:
```dart
import 'package:embarqueellus/services/face_image_processor.dart';
import 'dart:io';

void testFaceProcessing(String imagePath) async {
  final processor = FaceImageProcessor.instance;

  try {
    final file = File(imagePath);
    final processed = await processor.processFile(file, outputSize: 112);

    print('Imagem processada:');
    print('  Width: ${processed.width}');
    print('  Height: ${processed.height}');
    print('  Channels: ${processed.numChannels}');

    assert(processed.width == 112, 'Width deve ser 112');
    assert(processed.height == 112, 'Height deve ser 112');
    assert(processed.numChannels == 3, 'Deve ser RGB (3 canais)');

    print('✅ Processamento funcionando!');
  } catch (e) {
    print('❌ Erro: $e');
  }
}
```

**Checklist**:
- [ ] Imagem é recortada corretamente
- [ ] Dimensões são 112x112
- [ ] Formato é RGB (3 canais)
- [ ] Qualidade da imagem é boa

---

### Teste 5: Rotação EXIF (iOS)

**Importante para iOS 15.5+**

#### Procedimento:
1. Tire fotos em diferentes orientações:
   - Portrait (normal)
   - Landscape Left
   - Landscape Right
   - Portrait Upside Down

2. Verifique que todas são processadas corretamente

**Checklist**:
- [ ] Portrait: face orientada corretamente
- [ ] Landscape: face orientada corretamente
- [ ] Sem distorções
- [ ] Recorte preciso em todas orientações

---

### Teste 6: Integração com Embeddings

#### Código de Teste:
```dart
import 'package:embarqueellus/services/face_recognition_service.dart';

void testEmbeddingGeneration() async {
  final captureService = FaceCaptureService.instance;
  final recognitionService = FaceRecognitionService.instance;

  try {
    await captureService.initCamera();

    final result = await captureService.captureAndDetectFace();

    // Converter bytes para img.Image
    final image = img.decodeImage(result.croppedFaceBytes);

    if (image != null) {
      final embedding = await recognitionService.extractEmbedding(image);

      print('Embedding gerado:');
      print('  Dimensões: ${embedding.length}');
      print('  Primeiros 5 valores: ${embedding.take(5).toList()}');

      assert(embedding.length == 512, 'Embedding deve ter 512 dimensões');
      print('✅ Embeddings funcionando!');
    }
  } catch (e) {
    print('❌ Erro: $e');
  }
}
```

**Checklist**:
- [ ] Embedding é gerado sem erros
- [ ] Tamanho é 512 dimensões
- [ ] Valores estão normalizados
- [ ] Performance aceitável

---

## 🎯 Teste da Tela Completa

### Usar FaceCaptureScreen

1. Adicione ao seu app:

```dart
import 'package:embarqueellus/screens/face_capture_screen.dart';

// Em qualquer botão ou navegação
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => FaceCaptureScreen()),
);
```

2. Teste o fluxo completo:

**Checklist**:
- [ ] Preview da câmera aparece
- [ ] Guia circular é exibida
- [ ] Botão de captura funciona
- [ ] Mensagem de sucesso aparece
- [ ] Imagem capturada é exibida
- [ ] Tratamento de erro funciona

---

## 📊 Métricas de Qualidade Esperadas

### Performance

| Métrica | Valor Esperado |
|---------|----------------|
| Tempo de inicialização | < 2s |
| Tempo de captura | < 500ms |
| Tempo de detecção | < 600ms |
| Tempo de processamento | < 300ms |
| Tempo total | < 1.5s |

### Precisão

| Métrica | Valor Esperado |
|---------|----------------|
| Taxa de detecção | > 90% |
| Falsos positivos | < 5% |
| Qualidade de recorte | > 85% |

---

## 🐛 Problemas Conhecidos e Soluções

### Problema 1: "Nenhuma face detectada"

**Causas possíveis**:
- Iluminação insuficiente
- Face muito pequena na imagem
- Ângulo muito inclinado
- Imagem desfocada

**Solução**:
```dart
// Ajustar minFaceSize se necessário
minFaceSize: 0.05  // Detecta faces menores (5% da imagem)
```

---

### Problema 2: Rotação incorreta (iOS)

**Causa**: EXIF não aplicado

**Solução**: Já implementado em `face_image_processor.dart`:
```dart
final img.Image oriented = img.bakeOrientation(decoded);
```

---

### Problema 3: Formato de imagem incorreto

**Sintoma**: Erro ao converter imagem

**Solução**: Verificar formato configurado no CameraController:
```dart
// iOS
imageFormatGroup: ImageFormatGroup.bgra8888

// Android
imageFormatGroup: ImageFormatGroup.yuv420
```

---

## 📝 Relatório de Testes

Após executar todos os testes, preencha:

### Ambiente
- [ ] iOS 15.5+
- [ ] Android 6.0+
- Dispositivo: _____________
- Versão do SO: _____________

### Resultados

| Teste | Status | Observações |
|-------|--------|-------------|
| Compilação iOS | ⬜ | |
| Compilação Android | ⬜ | |
| Inicialização Câmera | ⬜ | |
| Captura de Foto | ⬜ | |
| Detecção Facial | ⬜ | |
| Processamento | ⬜ | |
| Rotação EXIF | ⬜ | |
| Geração Embeddings | ⬜ | |
| Tela Completa | ⬜ | |

### Issues Encontrados

1. _____________________________________________
2. _____________________________________________
3. _____________________________________________

---

## 🚀 Próximos Passos Após Testes

1. [ ] Ajustar parâmetros conforme métricas obtidas
2. [ ] Otimizar performance se necessário
3. [ ] Implementar testes unitários
4. [ ] Implementar testes de integração
5. [ ] Documentar casos de uso adicionais
6. [ ] Deploy em produção

---

**Importante**: Execute todos os testes em dispositivos reais (não emuladores) para resultados precisos de câmera e ML Kit.
