import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:embarqueellus/screens/face_capture_screen.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Exemplo de integração do FaceCaptureScreen com geração de embeddings
///
/// Este exemplo demonstra o fluxo completo de:
/// 1. Captura única de face
/// 2. Geração de embedding com ArcFace
/// 3. Armazenamento no banco de dados
/// 4. Reconhecimento facial
class FaceCaptureExample extends StatefulWidget {
  const FaceCaptureExample({super.key});

  @override
  State<FaceCaptureExample> createState() => _FaceCaptureExampleState();
}

class _FaceCaptureExampleState extends State<FaceCaptureExample> {
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();
  final DatabaseHelper _databaseHelper = DatabaseHelper();

  Uint8List? _capturedFaceImage;
  List<double>? _faceEmbedding;
  String? _recognitionResult;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      await _faceRecognitionService.initialize();
      Sentry.captureMessage('✅ FaceRecognitionService inicializado', level: SentryLevel.info);
    } catch (e) {
      Sentry.captureException(e, hint: Hint.withMap({'context': 'FaceCaptureExample.initializeServices'}));
    }
  }

  /// Abre a tela de captura facial
  Future<void> _openFaceCapture() async {
    try {
      // Navega para a tela de captura
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => FaceCaptureScreen(
            useFrontCamera: false, // Use câmera traseira
            onFaceCaptured: (faceImage) {
              // Callback opcional executado imediatamente após captura
              Sentry.captureMessage(
                '✅ Face capturada via callback: ${faceImage.lengthInBytes} bytes',
                level: SentryLevel.info,
              );
            },
          ),
        ),
      );

      // Verifica se houve sucesso
      if (result != null && result['success'] == true) {
        final Uint8List faceImage = result['faceImage'];
        await _processCapturedFace(faceImage);
      }
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({'context': 'FaceCaptureExample._openFaceCapture'}),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao capturar face: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Processa a face capturada gerando embedding
  Future<void> _processCapturedFace(Uint8List faceImage) async {
    setState(() {
      _isProcessing = true;
      _capturedFaceImage = faceImage;
    });

    try {
      Sentry.captureMessage(
        '🔄 Processando face capturada: ${faceImage.lengthInBytes} bytes',
        level: SentryLevel.info,
      );

      // 1. Gera embedding da face capturada
      final embedding = await _faceRecognitionService.extractEmbedding(faceImage);

      if (embedding == null) {
        throw Exception('Falha ao extrair embedding da face');
      }

      Sentry.captureMessage(
        '✅ Embedding gerado: ${embedding.length} dimensões',
        level: SentryLevel.info,
      );

      setState(() {
        _faceEmbedding = embedding;
      });

      // 2. Opcional: Tenta reconhecer a face
      await _recognizeFace(faceImage);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Face processada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({'context': 'FaceCaptureExample._processCapturedFace'}),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao processar face: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// Tenta reconhecer a face capturada
  Future<void> _recognizeFace(Uint8List faceImage) async {
    try {
      final result = await _faceRecognitionService.recognizeFace(faceImage);

      if (result != null && result['recognized'] == true) {
        setState(() {
          _recognitionResult =
              'Reconhecido: ${result['nome']}\n'
              'Confiança: ${(result['confidence'] * 100).toStringAsFixed(1)}%';
        });

        Sentry.captureMessage(
          '✅ Face reconhecida: ${result['nome']} (${result['confidence']})',
          level: SentryLevel.info,
        );
      } else {
        setState(() {
          _recognitionResult = 'Face não reconhecida';
        });

        Sentry.captureMessage(
          '⚠️ Face não reconhecida',
          level: SentryLevel.warning,
        );
      }
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({'context': 'FaceCaptureExample._recognizeFace'}),
      );
    }
  }

  /// Salva o embedding no banco de dados
  Future<void> _saveEmbedding() async {
    if (_faceEmbedding == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum embedding para salvar. Capture uma face primeiro.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Exemplo: solicita CPF e nome do usuário
    final cpf = await _showInputDialog('CPF', 'Digite o CPF da pessoa');
    if (cpf == null || cpf.isEmpty) return;

    final nome = await _showInputDialog('Nome', 'Digite o nome da pessoa');
    if (nome == null || nome.isEmpty) return;

    try {
      setState(() {
        _isProcessing = true;
      });

      // Salva no banco de dados
      await _databaseHelper.insertEmbedding(cpf, nome, _faceEmbedding!);

      Sentry.captureMessage(
        '✅ Embedding salvo: $nome ($cpf)',
        level: SentryLevel.info,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Embedding salvo para $nome'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({'context': 'FaceCaptureExample._saveEmbedding'}),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// Exibe dialog para entrada de texto
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
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _faceRecognitionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exemplo: Captura de Face'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Instruções
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'Como usar',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Clique em "Capturar Face"\n'
                      '2. Posicione o rosto no centro\n'
                      '3. Tire a foto\n'
                      '4. O embedding será gerado automaticamente\n'
                      '5. Opcionalmente, salve no banco de dados',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Botão de captura
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _openFaceCapture,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Capturar Face'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 16),

            // Imagem capturada
            if (_capturedFaceImage != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Face Capturada',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: Image.memory(_capturedFaceImage!),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tamanho: ${_capturedFaceImage!.lengthInBytes} bytes',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Informações do embedding
            if (_faceEmbedding != null) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'Embedding Gerado',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Dimensões: ${_faceEmbedding!.length}'),
                      Text(
                        'Primeiros valores: ${_faceEmbedding!.take(5).map((e) => e.toStringAsFixed(3)).join(", ")}...',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _saveEmbedding,
                        icon: const Icon(Icons.save),
                        label: const Text('Salvar no Banco'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Resultado do reconhecimento
            if (_recognitionResult != null) ...[
              Card(
                color: _recognitionResult!.contains('Reconhecido')
                    ? Colors.blue.shade50
                    : Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _recognitionResult!.contains('Reconhecido')
                                ? Icons.person_search
                                : Icons.person_off,
                            color: _recognitionResult!.contains('Reconhecido')
                                ? Colors.blue
                                : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Reconhecimento',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(_recognitionResult!),
                    ],
                  ),
                ),
              ),
            ],

            // Indicador de processamento
            if (_isProcessing) ...[
              const SizedBox(height: 16),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Processando...'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
