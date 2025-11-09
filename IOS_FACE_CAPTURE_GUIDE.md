# 📸 Guia de Captura Facial para iOS 15.5+

Documentação completa para usar o sistema de captura facial existente no iOS 15.5+ e Android.

---

## ✅ Correções Aplicadas para iOS 15.5

### Problema Identificado
O código anterior usava `ImageFormatGroup.bgra8888` no iOS, mas esse formato:
- ❌ Só funciona para **streaming** (`startImageStream`)
- ❌ NÃO funciona corretamente para `takePicture()` (captura única)
- ❌ Causava problemas de rotação e metadados EXIF incorretos

### Solução Implementada
✅ Alterado `FaceCameraView` para usar **`ImageFormatGroup.jpeg`**
- ✅ Formato universal (iOS e Android)
- ✅ Funciona perfeitamente com `takePicture()`
- ✅ Metadados EXIF corretos
- ✅ Rotação aplicada automaticamente pelo `img.bakeOrientation()`

**Arquivo modificado:** `lib/widgets/face_camera_view.dart` (linha 56)

---

## 🚀 Como Usar: Fluxo Completo de Captura Única

### 1. Estrutura de Arquivos Existentes

```
lib/
├── widgets/
│   └── face_camera_view.dart          ✅ Widget de captura única (CORRIGIDO)
├── services/
│   ├── face_detection_service.dart    ✅ Detecção facial ML Kit
│   ├── face_image_processor.dart      ✅ Processamento completo
│   ├── face_recognition_service.dart  ✅ Embeddings ArcFace
│   ├── camera_image_converter.dart    ✅ Conversão de formatos
│   ├── platform_camera_utils.dart     ✅ Rotação iOS/Android
│   └── yuv_converter.dart             ✅ Conversão YUV
└── database/
    └── database_helper.dart           ✅ Armazenamento SQLite
```

---

### 2. Exemplo de Uso Completo

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:embarqueellus/widgets/face_camera_view.dart';
import 'package:embarqueellus/services/face_image_processor.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/database/database_helper.dart';

class CapturaFacialScreen extends StatefulWidget {
  const CapturaFacialScreen({super.key});

  @override
  State<CapturaFacialScreen> createState() => _CapturaFacialScreenState();
}

class _CapturaFacialScreenState extends State<CapturaFacialScreen> {
  final _processor = FaceImageProcessor.instance;
  final _faceRecognition = FaceRecognitionService();
  final _database = DatabaseHelper();

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _faceRecognition.initialize();
  }

  /// Callback chamado quando a foto é capturada
  Future<void> _onPhotoCapture(XFile photo) async {
    setState(() => _isProcessing = true);

    try {
      print('📸 Foto capturada: ${photo.path}');

      // PASSO 1: Processar imagem (detectar + recortar + alinhar + normalizar)
      // - Detecta face com ML Kit
      // - Seleciona face principal (maior área)
      // - Alinha automaticamente baseado em landmarks dos olhos
      // - Recorta com margem de 28%
      // - Normaliza orientação EXIF (img.bakeOrientation)
      // - Redimensiona para 112x112 RGB (pronto para ArcFace)
      final img.Image faceProcessed = await _processor.processFile(
        File(photo.path),
        outputSize: 112, // Tamanho para modelo ArcFace
      );

      print('✅ Face processada: ${faceProcessed.width}x${faceProcessed.height}');

      // PASSO 2: Converter para bytes
      final Uint8List imageBytes = Uint8List.fromList(
        img.encodeJpg(faceProcessed, quality: 95),
      );

      // PASSO 3: Gerar embedding com ArcFace (512 dimensões)
      final List<double>? embedding = await _faceRecognition.extractEmbedding(
        imageBytes,
      );

      if (embedding == null) {
        throw Exception('Falha ao gerar embedding facial');
      }

      print('✅ Embedding gerado: ${embedding.length} dimensões');
      print('   Primeiros valores: ${embedding.take(5).toList()}');

      // PASSO 4 (Opcional): Reconhecer face existente
      final resultado = await _faceRecognition.recognizeFace(imageBytes);

      if (resultado != null && resultado['recognized'] == true) {
        print('✅ Face reconhecida: ${resultado['nome']}');
        print('   Confiança: ${(resultado['confidence'] * 100).toStringAsFixed(1)}%');

        _showSuccess('Face reconhecida: ${resultado['nome']}');
      } else {
        print('⚠️ Face não reconhecida no banco de dados');

        // PASSO 5: Salvar nova face (opcional)
        await _saveNewFace(embedding);
      }

      // Retornar resultado
      if (mounted) {
        Navigator.pop(context, {
          'success': true,
          'embedding': embedding,
          'imageBytes': imageBytes,
          'recognized': resultado,
        });
      }

    } catch (e, stackTrace) {
      print('❌ Erro ao processar face: $e');
      print('Stack trace: $stackTrace');

      _showError(e.toString());

    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Salva nova face no banco de dados
  Future<void> _saveNewFace(List<double> embedding) async {
    // Solicitar informações do usuário
    final cpf = await _showInputDialog('CPF', 'Digite o CPF');
    if (cpf == null || cpf.isEmpty) return;

    final nome = await _showInputDialog('Nome', 'Digite o nome completo');
    if (nome == null || nome.isEmpty) return;

    // Salvar no banco
    await _database.insertEmbedding(cpf, nome, embedding);

    print('✅ Embedding salvo para: $nome ($cpf)');
    _showSuccess('Cadastro facial realizado com sucesso!');
  }

  Future<String?> _showInputDialog(String title, String hint) async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erro: $message'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  void dispose() {
    _faceRecognition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Widget de câmera (já corrigido para iOS 15.5)
          FaceCameraView(
            useFrontCamera: false, // true = frontal, false = traseira
            onCapture: _onPhotoCapture,
          ),

          // Overlay de processamento
          if (_isProcessing)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Processando face...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Detectando, recortando e gerando embedding',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

---

## 📊 Fluxo de Processamento Detalhado

```
┌────────────────────────┐
│  Usuário abre tela     │
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│  FaceCameraView        │
│  (formato JPEG) ✅     │
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│  Usuário tira foto     │
│  takePicture()         │
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│  XFile retornado       │
│  (JPEG com EXIF) ✅    │
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│  processFile()         │
│  - Lê arquivo          │
│  - Decodifica imagem   │
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│  bakeOrientation() ✅  │
│  (aplica EXIF)         │
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│  Detecção ML Kit       │
│  (faces encontradas)   │
└───────────┬────────────┘
            │
      ┌─────┴─────┐
      │           │
      ▼           ▼
 Nenhuma      Faces OK
  face            │
   │              ▼
   │    ┌─────────────────┐
   │    │  Seleciona maior│
   │    │  (face principal)│
   │    └────────┬─────────┘
   │             │
   │             ▼
   │    ┌─────────────────┐
   │    │  Alinhamento    │
   │    │  dos olhos ✅   │
   │    └────────┬─────────┘
   │             │
   │             ▼
   │    ┌─────────────────┐
   │    │  Crop + margem  │
   │    │  28% ✅         │
   │    └────────┬─────────┘
   │             │
   │             ▼
   │    ┌─────────────────┐
   │    │  Resize 112x112 │
   │    │  RGB ✅         │
   │    └────────┬─────────┘
   │             │
   │             ▼
   │    ┌─────────────────┐
   │    │  ArcFace Model  │
   │    │  (512D embedding)│
   │    └────────┬─────────┘
   │             │
   │             ▼
   └───────► SUCESSO
              │
              ▼
      Salvar/Reconhecer
```

---

## 🎯 Especificações Técnicas iOS 15.5

### Formato de Câmera
- **Captura única**: `ImageFormatGroup.jpeg` ✅
- **Streaming**: `ImageFormatGroup.bgra8888` (se precisar usar startImageStream)

### Rotação
- **Automática**: `img.bakeOrientation()` aplica metadados EXIF
- **Platform-specific**: `PlatformCameraUtils` calcula rotação correta para iOS

### Resolução
- **Preset**: `ResolutionPreset.high` (1920x1080 ou maior)
- **Output**: 112x112 pixels (após processamento)

### ML Kit Face Detection
- **Mode**: `FaceDetectorMode.fast` (padrão)
- **Landmarks**: Habilitados (para alinhamento dos olhos)
- **Tracking**: Habilitado

### ArcFace Model
- **Input**: 112x112 RGB
- **Output**: 512 dimensões (L2 normalized)
- **Threshold**: 1.1 (distância Euclidiana)

---

## ⚠️ Problemas Comuns e Soluções

### 1. "Nenhum rosto detectado"

**Causas:**
- Iluminação insuficiente
- Rosto muito pequeno/grande
- Ângulo inadequado
- Foto desfocada

**Soluções:**
```dart
// Ajustar minFaceSize no FaceDetectionService
FaceDetector(
  options: FaceDetectorOptions(
    minFaceSize: 0.1, // Padrão: 0.1 (10% da imagem)
    // Reduzir para 0.05 se rostos muito pequenos
    // Aumentar para 0.15 se muitos falsos positivos
  ),
)
```

### 2. "Face cortada incorretamente"

**Causa:**
- Margem de 28% pode ser insuficiente

**Solução:**
```dart
// Aumentar margem em face_image_processor.dart (linha 367)
const double padding = 0.35; // Aumentar de 0.28 para 0.35
```

### 3. "Rotação incorreta no iOS"

**Causa:**
- Metadados EXIF ausentes ou incorretos

**Solução:**
```dart
// Verificar se bakeOrientation está sendo chamado
final img.Image baked = img.bakeOrientation(decoded!);
// Isso já está implementado na linha 237 de face_image_processor.dart ✅
```

### 4. "Embedding sempre diferente"

**Causa:**
- Variações de iluminação, ângulo ou alinhamento

**Solução:**
- Use **múltiplas fotos** para enrollment (FaceRecognitionService já suporta)
- Calcule embedding médio de 3-5 fotos

```dart
// Exemplo: cadastrar com múltiplas fotos
final embeddings = <List<double>>[];

for (int i = 0; i < 3; i++) {
  // Capturar foto
  final embedding = await extractEmbedding(foto);
  embeddings.add(embedding);
}

// Calcular média
final avgEmbedding = FaceRecognitionService.averageEmbeddings(embeddings);
await database.insertEmbedding(cpf, nome, avgEmbedding);
```

---

## 🔍 Debug e Logs

### Sentry
Todos os processos possuem logs detalhados enviados ao Sentry:

```dart
// Logs disponíveis:
// ✅ DETECTOR: Criação e configuração do FaceDetector
// ✅ DETECTION: Detecção de faces (quantidade, bounding boxes)
// ✅ PROCESSOR: Processamento de imagem (decode, crop, resize)
// ✅ ROTATION: Cálculo de rotação (iOS vs Android)
// ✅ CONVERTER: Conversão de formatos
// ✅ FORMAT: Identificação de formato de imagem
```

### Logs Locais
Para habilitar logs detalhados no console:

```dart
// Em processCameraImage (apenas streaming)
final result = await processor.processCameraImage(
  image,
  camera: camera,
  enableDebugLogs: true, // ✅ Habilita logs detalhados
);
```

---

## ✅ Checklist de Compatibilidade iOS 15.5

- [x] Formato JPEG para captura única
- [x] bakeOrientation() para normalizar rotação EXIF
- [x] Rotação específica iOS em PlatformCameraUtils
- [x] Alinhamento automático dos olhos
- [x] Margem de 28% no crop
- [x] Redimensionamento para 112x112 RGB
- [x] Logs detalhados via Sentry
- [x] Tratamento de erros robusto
- [x] Permissões configuradas no Info.plist
- [x] Podfile com platform :ios, '15.5'

---

## 📞 Referências

- **ML Kit Face Detection**: https://developers.google.com/ml-kit/vision/face-detection
- **Camera Plugin**: https://pub.dev/packages/camera
- **Image Package**: https://pub.dev/packages/image
- **ArcFace Paper**: https://arxiv.org/abs/1801.07698

---

**Última atualização**: 2025-01-09
**Versão**: 1.0.0
**Compatibilidade**: iOS 15.5+, Android 5.0+
**Status**: ✅ Testado e funcional
