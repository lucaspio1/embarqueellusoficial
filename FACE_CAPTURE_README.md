# 📸 Módulo de Captura Única + Detecção Facial

Documentação completa do módulo de captura única de face com detecção e recorte facial para Flutter.

## 🎯 Visão Geral

Este módulo implementa um fluxo completo de captura única de imagem com detecção facial, recorte e preparação para geração de embeddings faciais.

### Funcionalidades

✅ Captura única de foto (não streaming)
✅ Detecção facial com ML Kit
✅ Recorte automático da região facial
✅ Margem de segurança de 20% no recorte
✅ Retorno de `Uint8List` pronto para embeddings
✅ UI intuitiva com guias visuais
✅ Compatibilidade total com iOS 15.5+ e Android
✅ Logs detalhados via Sentry

---

## 📁 Estrutura de Arquivos

```
lib/
├── services/
│   └── single_face_capture_service.dart  # Serviço de captura e processamento
├── screens/
│   ├── face_capture_screen.dart          # Tela de captura única
│   └── face_capture_example.dart         # Exemplo de integração
```

---

## 🚀 Como Usar

### 1. Uso Básico

```dart
import 'package:embarqueellus/screens/face_capture_screen.dart';

// Navegar para a tela de captura
final result = await Navigator.push<Map<String, dynamic>>(
  context,
  MaterialPageRoute(
    builder: (context) => FaceCaptureScreen(
      useFrontCamera: false, // false = traseira, true = frontal
    ),
  ),
);

// Processar resultado
if (result != null && result['success'] == true) {
  final Uint8List faceImage = result['faceImage'];
  final Rect boundingBox = result['boundingBox'];

  print('Face capturada: ${faceImage.lengthInBytes} bytes');
  print('Região: ${boundingBox.width}x${boundingBox.height}');
}
```

### 2. Uso com Callback

```dart
FaceCaptureScreen(
  useFrontCamera: false,
  onFaceCaptured: (faceImage) {
    // Executado imediatamente após captura
    print('Face capturada: ${faceImage.lengthInBytes} bytes');
  },
)
```

### 3. Integração com Embeddings

```dart
import 'package:embarqueellus/services/face_recognition_service.dart';

// 1. Capturar face
final result = await Navigator.push<Map<String, dynamic>>(
  context,
  MaterialPageRoute(builder: (context) => FaceCaptureScreen()),
);

if (result != null && result['success'] == true) {
  final Uint8List faceImage = result['faceImage'];

  // 2. Gerar embedding com ArcFace
  final faceRecognitionService = FaceRecognitionService();
  await faceRecognitionService.initialize();

  final embedding = await faceRecognitionService.extractEmbedding(faceImage);

  if (embedding != null) {
    print('Embedding gerado: ${embedding.length} dimensões');

    // 3. Salvar no banco ou usar para reconhecimento
    await databaseHelper.insertEmbedding(cpf, nome, embedding);
  }
}
```

---

## 🔧 API do SingleFaceCaptureService

### Métodos Principais

#### `captureAndDetectFace(CameraController controller)`

Captura uma única imagem e processa a face.

**Parâmetros:**
- `controller`: CameraController já inicializado

**Retorna:**
```dart
Map<String, dynamic> {
  'faceImage': Uint8List,      // Imagem recortada da face
  'boundingBox': Rect,         // Coordenadas da face detectada
  'confidence': double,        // Confiança da detecção (sempre 1.0)
  'imageWidth': double,        // Largura do recorte
  'imageHeight': double,       // Altura do recorte
}
```

**Exceções:**
- `Exception`: Se nenhuma face for detectada
- `Exception`: Se CameraController não estiver inicializado
- `Exception`: Se ocorrer erro no processamento

### Configuração do Detector

```dart
FaceDetector(
  options: FaceDetectorOptions(
    performanceMode: FaceDetectorMode.accurate,  // Modo preciso
    enableContours: false,                       // Contornos desabilitados
    enableLandmarks: true,                       // Marcos faciais (olhos, nariz)
    enableClassification: false,                 // Classificação desabilitada
    minFaceSize: 0.1,                           // Face mínima: 10% da imagem
  ),
);
```

---

## 🎨 UI do FaceCaptureScreen

### Componentes Visuais

1. **Preview da Câmera**: Preview em tempo real
2. **Overlay com Guia Oval**: Área de posicionamento sugerida
3. **Instruções**: Orientações para o usuário
4. **Botão de Captura**: Botão circular grande para captura
5. **Indicador de Processamento**: Overlay durante processamento

### Estados da Tela

| Estado | Descrição |
|--------|-----------|
| `_isInitializing` | Câmera sendo inicializada |
| `_isProcessing` | Face sendo processada |
| `_errorMessage` | Erro durante captura/processamento |

---

## ⚙️ Configuração

### Dependências (já configuradas)

```yaml
dependencies:
  camera: ^0.10.5+9
  google_mlkit_face_detection: ^0.13.1
  image: ^4.0.17
  path_provider: ^2.1.3
  sentry_flutter: ^9.8.0
```

### Permissões iOS (Info.plist)

```xml
<key>NSCameraUsageDescription</key>
<string>Este app utiliza a câmera para capturar o rosto do usuário.</string>
```

### Permissões Android (AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="true" />
```

### Plataforma iOS (Podfile)

```ruby
platform :ios, '15.5'
```

---

## 📊 Fluxo de Processamento

```
┌─────────────────────┐
│  Usuário abre tela  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Inicializa câmera  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   Preview da câmera │◄──┐
└──────────┬──────────┘   │
           │               │
           ▼               │
┌─────────────────────┐   │
│  Usuário tira foto  │   │
└──────────┬──────────┘   │
           │               │
           ▼               │
┌─────────────────────┐   │
│  Captura imagem     │   │
└──────────┬──────────┘   │
           │               │
           ▼               │
┌─────────────────────┐   │
│ Detecta faces (ML)  │   │
└──────────┬──────────┘   │
           │               │
     ┌─────┴─────┐         │
     │           │         │
     ▼           ▼         │
  Nenhuma    Múltiplas     │
   face        faces       │
     │           │         │
     └─────┬─────┘         │
           │               │
      ┌────▼────┐          │
      │  ERRO   │──────────┘
      └─────────┘  Retry
           │
           ▼
     Face detectada
           │
           ▼
┌─────────────────────┐
│  Seleciona maior    │
│  face (principal)   │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Recorta com margem  │
│   de segurança      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Codifica JPEG      │
│   (qualidade 95%)   │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Retorna Uint8List  │
└─────────────────────┘
```

---

## 🔍 Detalhes Técnicos

### Recorte da Face

- **Margem de segurança**: 20% em cada lado
- **Cálculo das coordenadas**:
  ```dart
  marginX = boundingBox.width * 0.20
  marginY = boundingBox.height * 0.20

  x = max(0, boundingBox.left - marginX)
  y = max(0, boundingBox.top - marginY)
  width = min(imageWidth - x, boundingBox.width + 2*marginX)
  height = min(imageHeight - y, boundingBox.height + 2*marginY)
  ```

### Seleção de Face Principal

Quando múltiplas faces são detectadas, seleciona-se a face com maior área:

```dart
Face primaryFace = faces.reduce((current, next) {
  final currentArea = current.boundingBox.width * current.boundingBox.height;
  final nextArea = next.boundingBox.width * next.boundingBox.height;
  return currentArea > nextArea ? current : next;
});
```

### Formato de Imagem

- **Captura**: JPEG (universal iOS/Android)
- **Codificação final**: JPEG com qualidade 95%
- **Retorno**: `Uint8List` (array de bytes)

---

## 📝 Exemplo Completo

Veja o arquivo [`face_capture_example.dart`](lib/screens/face_capture_example.dart) para um exemplo completo de integração com:

- Captura de face
- Geração de embedding
- Reconhecimento facial
- Salvamento no banco de dados

---

## 🐛 Troubleshooting

### Erro: "Nenhuma face detectada"

**Possíveis causas:**
- Iluminação insuficiente
- Rosto muito pequeno na imagem
- Rosto muito próximo/distante
- Ângulo inadequado

**Solução:**
- Garantir boa iluminação
- Ajustar `minFaceSize` no FaceDetectorOptions
- Orientar usuário a centralizar rosto

### Erro: "Câmera não inicializada"

**Causa:** CameraController não foi inicializado corretamente

**Solução:**
```dart
await _cameraController.initialize();
// Verificar se está inicializado
if (!_cameraController.value.isInitialized) {
  // Tentar novamente ou exibir erro
}
```

### Erro de permissão de câmera

**iOS:** Verificar `NSCameraUsageDescription` no Info.plist
**Android:** Verificar `CAMERA` permission no AndroidManifest.xml
**Runtime:** Solicitar permissão antes de abrir a tela

---

## 📱 Compatibilidade

| Plataforma | Versão Mínima | Status |
|------------|---------------|--------|
| iOS        | 15.5          | ✅ Testado |
| Android    | API 21 (5.0)  | ✅ Compatível |

---

## 🔐 Privacidade e Segurança

1. **Arquivo temporário**: Automaticamente deletado após processamento
2. **Dados em memória**: `Uint8List` gerenciado pelo Dart GC
3. **Logs sensíveis**: Enviados apenas para Sentry (não armazenados localmente)
4. **Permissões**: Solicitadas apenas quando necessário

---

## 📞 Suporte

Para dúvidas ou problemas:
1. Verifique os logs do Sentry
2. Consulte o arquivo `face_capture_example.dart`
3. Revise a documentação do ML Kit: https://developers.google.com/ml-kit/vision/face-detection

---

## 🎯 Próximos Passos

Após capturar a face, você pode:

1. **Gerar embedding**: Use `FaceRecognitionService.extractEmbedding()`
2. **Reconhecer face**: Use `FaceRecognitionService.recognizeFace()`
3. **Salvar no banco**: Use `DatabaseHelper.insertEmbedding()`
4. **Processar com ArcFace**: O recorte já está otimizado para o modelo

---

**Versão**: 1.0.0
**Última atualização**: 2025-01-09
**Compatibilidade**: Flutter 3.0+, iOS 15.5+, Android 5.0+
