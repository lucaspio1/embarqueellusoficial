// lib/screens/controle_alunos_screen.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/face_image_processor.dart';
import 'package:embarqueellus/services/alunos_sync_service.dart';
import 'package:embarqueellus/services/offline_sync_service.dart';
import 'package:embarqueellus/services/face_detection_service.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ControleAlunosScreen extends StatefulWidget {
  const ControleAlunosScreen({super.key});

  @override
  State<ControleAlunosScreen> createState() => _ControleAlunosScreenState();
}

class _ControleAlunosScreenState extends State<ControleAlunosScreen> {
  final _db = DatabaseHelper.instance;
  final _faceService = FaceRecognitionService.instance;
  final _syncService = AlunosSyncService.instance;
  final TextEditingController _nomeController = TextEditingController();

  List<Map<String, dynamic>> _todosAlunos = [];
  List<Map<String, dynamic>> _alunos = [];
  List<Map<String, dynamic>> _alunosFiltrados = [];
  bool _carregando = true;
  bool _processando = false;
  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _nomeController.addListener(_filtrarAlunos);
    _inicializar();
  }

  @override
  void dispose() {
    _nomeController.removeListener(_filtrarAlunos);
    _nomeController.dispose();
    super.dispose();
  }

  void _filtrarAlunos() => setState(() {});

  Future<void> _inicializar() async {
    setState(() => _carregando = true);

    final temAlunos = await _syncService.temAlunosLocais();

    if (!temAlunos) {
      print('📥 [ControleAlunos] Nenhum aluno local, tentando sincronizar...');
      await _sincronizarAlunos(mostrarMensagem: false);
    }

    await _carregarAlunos();
  }

  Future<void> _carregarAlunos() async {
    setState(() => _carregando = true);
    try {
      // Buscar TODOS os passageiros da tabela passageiros (carregados pelo QR Code)
      final todosPassageiros = await _db.getPassageiros();

      final prefs = await SharedPreferences.getInstance();
      final facialLiberada =
          (prefs.getString('pulseira') ?? '').toUpperCase() == 'SIM';

      // Garantir que esses passageiros existam na tabela alunos para facial
      for (final passageiro in todosPassageiros) {
        final cpf = passageiro.cpf;
        if (cpf == null || cpf.isEmpty) continue; // Pular se CPF for null ou vazio

        final alunoExistente = await _db.getAlunoByCpf(cpf);
        if (alunoExistente == null) {
          // Criar registro na tabela alunos
          await _db.upsertAluno({
            'cpf': cpf,
            'nome': passageiro.nome,
            'email': '',
            'telefone': '',
            'turma': passageiro.turma ?? '',
            'facial': facialLiberada ? 'NAO' : 'BLOQUEADA',
            'tem_qr': facialLiberada ? 'SIM' : 'NAO',
          });
        }
      }

      // Agora buscar os alunos da tabela alunos com tem_qr='SIM'
      final alunos = await _db.getAlunosEmbarcadosParaCadastro();

      setState(() {
        _alunos = alunos;
        _alunosFiltrados = alunos;
        _todosAlunos = alunos;
        _carregando = false;
      });

      print('📋 ${_alunos.length} alunos carregados para cadastro facial');
    } catch (e) {
      print('❌ Erro ao carregar alunos: $e');
      setState(() => _carregando = false);
    }
  }

  Future<void> _sincronizarAlunos({bool mostrarMensagem = true}) async {
    setState(() => _sincronizando = true);

    try {
      if (mostrarMensagem) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 16),
                Text('Sincronizando alunos...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      final result = await _syncService.syncAlunosFromSheets();

      if (result.success) {
        await _carregarAlunos();

        if (mounted && mostrarMensagem) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${result.message}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted && mostrarMensagem) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${result.message}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ [ControleAlunos] Erro ao sincronizar: $e');
      if (mounted && mostrarMensagem) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _sincronizando = false);
    }
  }

  Future<String?> _abrirCameraTela({bool frontal = true}) async {
    final cameras = await availableCameras();
    final camera = cameras.firstWhere(
          (c) => frontal
          ? c.lensDirection == CameraLensDirection.front
          : c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    return await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraPreviewScreen(camera: camera),
      ),
    );
  }

  Future<img.Image> _processarImagemParaModelo(File imageFile) async {
    try {
      return await FaceImageProcessor.instance.processFile(
        imageFile,
        outputSize: FaceRecognitionService.INPUT_SIZE,
      );
    } catch (e) {
      throw Exception('Falha ao preparar imagem facial: $e');
    }
  }

  Future<void> _cadastrarFacial(Map<String, dynamic> aluno) async {
    try {
      final imagePath = await _abrirCameraTela(frontal: true);
      if (imagePath == null) return;

      setState(() => _processando = true);
      _mostrarProgresso('Validando rosto na imagem...');

      // ✅ Validar que há um rosto na foto usando MLKit
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await FaceDetectionService.instance.detect(inputImage);

      if (faces.isEmpty) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        setState(() => _processando = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Nenhum rosto detectado na foto. Tente novamente.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      if (faces.length > 1) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        setState(() => _processando = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Múltiplos rostos detectados. Certifique-se de que apenas uma pessoa está na foto.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      _atualizarProgresso('Processando imagem...');

      final processedImage = await _processarImagemParaModelo(File(imagePath));

      _atualizarProgresso('Extraindo características faciais...');

      // ✅ CORREÇÃO: Extrair embedding diretamente (SEM salvar em 'embeddings')
      final embedding = await _faceService.extractEmbedding(processedImage);

      print('📤 [CadastroFacial] Embedding extraído: ${embedding.length} dimensões');

      // ✅ Salvar APENAS na tabela pessoas_facial (fonte única da verdade)
      await _db.upsertPessoaFacial({
        'cpf': aluno['cpf'],
        'nome': aluno['nome'],
        'email': aluno['email'] ?? '',
        'telefone': aluno['telefone'] ?? '',
        'turma': aluno['turma'] ?? '',
        'embedding': jsonEncode(embedding),
        'facial_status': 'CADASTRADA',
      });

      print('✅ [CadastroFacial] Salvo na tabela pessoas_facial');

      await OfflineSyncService.instance.queueCadastroFacial(
        cpf: aluno['cpf'],
        nome: aluno['nome'],
        email: aluno['email'] ?? '',
        telefone: aluno['telefone'] ?? '',
        embedding: embedding,
        personId: aluno['cpf'],
      );

      print('✅ [CadastroFacial] Embedding enfileirado para sincronização com aba Pessoas');

      // Sincronizar em background (não bloqueia a UI)
      OfflineSyncService.instance.trySyncInBackground();
      print('🔄 [CadastroFacial] Sincronização em background iniciada');

      await _db.updateAlunoFacial(aluno['cpf'], 'CADASTRADA');

      if (Navigator.canPop(context)) Navigator.pop(context);
      setState(() => _processando = false);

      await _carregarAlunos();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('✅ Facial cadastrada: ${aluno['nome']}',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('☁️ Sincronizando em segundo plano...'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      print('❌ Erro ao cadastrar facial: $e');
      if (Navigator.canPop(context)) Navigator.pop(context);
      setState(() => _processando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Erro ao cadastrar facial: $e')),
      );
    }
  }

  Future<void> _cadastrarFacialAvancado(Map<String, dynamic> aluno) async {
    try {
      List<img.Image> faces = [];

      for (int i = 1; i <= 3; i++) {
        _mostrarProgresso('Captura $i/3: Posicione o rosto e olhe para a câmera');

        final imagePath = await _abrirCameraTela(frontal: true);
        if (imagePath == null) continue;

        // ✅ Validar que há um rosto na foto usando MLKit
        final inputImage = InputImage.fromFilePath(imagePath);
        final detectedFaces = await FaceDetectionService.instance.detect(inputImage);

        if (detectedFaces.isEmpty) {
          if (Navigator.canPop(context)) Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Nenhum rosto detectado na captura $i. Tente novamente.'),
              backgroundColor: Colors.red,
            ),
          );
          continue; // Permitir nova tentativa
        }

        if (detectedFaces.length > 1) {
          if (Navigator.canPop(context)) Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Múltiplos rostos detectados na captura $i. Tente novamente.'),
              backgroundColor: Colors.orange,
            ),
          );
          continue; // Permitir nova tentativa
        }

        final processedImage = await _processarImagemParaModelo(File(imagePath));
        faces.add(processedImage);

        if (i < 3) {
          await Future.delayed(Duration(seconds: 1));
        }
      }

      if (faces.isEmpty) {
        throw Exception('Nenhuma imagem capturada');
      }

      _atualizarProgresso('Processando ${faces.length} imagens...');

      // ✅ CORREÇÃO: Extrair embedding avançado diretamente (SEM salvar em 'embeddings')
      // Calcular média dos embeddings das múltiplas fotos
      final embeddings = <List<double>>[];
      for (final face in faces) {
        final emb = await _faceService.extractEmbedding(face);
        embeddings.add(emb);
      }

      // Média dos embeddings para melhor precisão
      final embedding = List<double>.filled(embeddings[0].length, 0.0);
      for (final emb in embeddings) {
        for (int i = 0; i < emb.length; i++) {
          embedding[i] += emb[i] / embeddings.length;
        }
      }

      print('📤 [CadastroFacialAvançado] Embedding extraído de ${faces.length} fotos: ${embedding.length} dimensões');

      // ✅ Salvar APENAS na tabela pessoas_facial (fonte única da verdade)
      await _db.upsertPessoaFacial({
        'cpf': aluno['cpf'],
        'nome': aluno['nome'],
        'email': aluno['email'] ?? '',
        'telefone': aluno['telefone'] ?? '',
        'turma': aluno['turma'] ?? '',
        'embedding': jsonEncode(embedding),
        'facial_status': 'CADASTRADA',
      });

      print('✅ [CadastroFacialAvançado] Salvo na tabela pessoas_facial');

      await OfflineSyncService.instance.queueCadastroFacial(
        cpf: aluno['cpf'],
        nome: aluno['nome'],
        email: aluno['email'] ?? '',
        telefone: aluno['telefone'] ?? '',
        embedding: embedding,
        personId: aluno['cpf'],
      );

      print('✅ [CadastroFacialAvançado] Embedding enfileirado para sincronização com aba Pessoas');

      // Sincronizar em background (não bloqueia a UI)
      OfflineSyncService.instance.trySyncInBackground();
      print('🔄 [CadastroFacialAvançado] Sincronização em background iniciada');

      await _db.updateAlunoFacial(aluno['cpf'], 'CADASTRADA');

      if (Navigator.canPop(context)) Navigator.pop(context);
      setState(() => _processando = false);

      await _carregarAlunos();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('✅ Facial cadastrada com alta precisão!',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('${aluno['nome']} - ${faces.length} imagens processadas'),
              Text('☁️ Sincronizando em segundo plano...'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      print('❌ Erro ao cadastrar facial avançada: $e');
      if (Navigator.canPop(context)) Navigator.pop(context);
      setState(() => _processando = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final alunosFiltrados = _todosAlunos.where((a) {
      final filtro = _nomeController.text.toLowerCase();
      return a['nome'].toLowerCase().contains(filtro);
    }).toList();

    final totalComFacial =
        _todosAlunos.where((a) => a['facial'] == 'CADASTRADA').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Alunos'),
        backgroundColor: const Color(0xFF4C643C),
        actions: [
          if (_sincronizando)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.cloud_download),
              onPressed: _sincronizarAlunos,
              tooltip: 'Sincronizar com planilha',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarAlunos,
            tooltip: 'Atualizar',
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: () async {
              // Sincronizar em background
              OfflineSyncService.instance.trySyncInBackground();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('☁️ Sincronização iniciada em segundo plano'),
                  backgroundColor: Colors.blue,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Sincronizar embeddings',
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildHeader(_todosAlunos.length, totalComFacial),

          if (_todosAlunos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Icon(
                    Icons.cloud_off,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Nenhum aluno encontrado',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sincronize com a planilha para carregar os alunos',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _sincronizarAlunos,
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('SINCRONIZAR AGORA'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4C643C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _nomeController,
                decoration: const InputDecoration(
                  labelText: 'Buscar aluno',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: alunosFiltrados.length,
                itemBuilder: (context, index) {
                  final aluno = alunosFiltrados[index];
                  final temFacial = aluno['facial'] == 'CADASTRADA';
                  return Card(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: temFacial
                            ? Colors.green.shade100
                            : Colors.red.shade50,
                        child: Icon(
                          temFacial
                              ? Icons.verified_user
                              : Icons.face_retouching_off,
                          color: temFacial
                              ? Colors.green.shade700
                              : Colors.red.shade400,
                        ),
                      ),
                      title: Text(aluno['nome'] ?? 'Sem nome'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CPF: ${aluno['cpf'] ?? '--'}'),
                          if (aluno['turma'] != null && aluno['turma'].toString().isNotEmpty)
                            Text('Turma: ${aluno['turma']}'),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'simples') {
                            _cadastrarFacial(aluno);
                          } else if (value == 'avancado') {
                            _cadastrarFacialAvancado(aluno);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'simples',
                            child: Row(
                              children: [
                                Icon(Icons.face, color: Colors.grey),
                                SizedBox(width: 8),
                                Text('Cadastro Simples'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'avancado',
                            child: Row(
                              children: [
                                Icon(Icons.verified_user, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Cadastro Avançado (3 fotos)'),
                              ],
                            ),
                          ),
                        ],
                        child: ElevatedButton(
                          onPressed: () => _cadastrarFacial(aluno),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4C643C),
                            foregroundColor: Colors.white,
                          ),
                          child: Text(temFacial ? 'Refazer' : 'Cadastrar'),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(int totalAlunos, int totalComFacial) {
    final porcentagem = totalAlunos > 0
        ? ((totalComFacial / totalAlunos) * 100).toStringAsFixed(0)
        : '0';

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4C643C), Color(0xFF3A4F2A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.face, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Cadastro de Faciais',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatCard('Total', totalAlunos.toString(), Icons.people),
              _buildStatCard(
                  'Com Facial', totalComFacial.toString(), Icons.verified_user),
              _buildStatCard('Progresso', '$porcentagem%', Icons.trending_up),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _mostrarProgresso(String mensagem) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF4C643C)),
              const SizedBox(height: 20),
              Text(mensagem, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  void _atualizarProgresso(String mensagem) {
    if (Navigator.canPop(context)) Navigator.pop(context);
    _mostrarProgresso(mensagem);
  }
}

class CameraPreviewScreen extends StatefulWidget {
  final CameraDescription camera;
  const CameraPreviewScreen({required this.camera});

  @override
  State<CameraPreviewScreen> createState() => _CameraPreviewScreenState();
}

class _CameraPreviewScreenState extends State<CameraPreviewScreen> {
  CameraController? controller;
  bool _tirandoFoto = false;
  bool _disposed = false;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadCamerasAndInitialize();
  }

  Future<void> _loadCamerasAndInitialize() async {
    try {
      _cameras = await availableCameras();

      _currentCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == widget.camera.lensDirection,
      );
      if (_currentCameraIndex == -1) _currentCameraIndex = 0;

      await _initializeCamera();
    } catch (e) {
      print('❌ Erro ao carregar câmeras: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _initializeCamera() async {
    try {
      if (_cameras.isEmpty) return;

      controller = CameraController(
        _cameras[_currentCameraIndex],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller!.initialize();

      if (mounted && !_disposed) {
        setState(() {});
      }
    } catch (e) {
      print('❌ Erro ao inicializar câmera: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _trocarCamera() async {
    if (_cameras.length < 2) return;

    setState(() => _tirandoFoto = true);

    try {
      await controller?.dispose();
      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
      await _initializeCamera();
      setState(() => _tirandoFoto = false);
    } catch (e) {
      print('❌ Erro ao trocar câmera: $e');
      setState(() => _tirandoFoto = false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (controller?.value.isInitialized == true) {
      controller!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Capturar Rosto'),
          backgroundColor: const Color(0xFF4C643C),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                'Inicializando câmera...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capturar rosto'),
        backgroundColor: const Color(0xFF4C643C),
        actions: [
          if (_cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              onPressed: _tirandoFoto ? null : _trocarCamera,
              tooltip: 'Trocar Câmera',
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 📸 CÂMERA PREENCHENDO TODA A TELA (proporção correta, sem distorção)
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller!.value.previewSize!.height,
                height: controller!.value.previewSize!.width,
                child: CameraPreview(controller!),
              ),
            ),
          ),

          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Card(
                color: Colors.black54,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Posicione o rosto dentro da moldura',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_cameras.length > 1)
                        const SizedBox(height: 4),
                      if (_cameras.length > 1)
                        Text(
                          _cameras[_currentCameraIndex].lensDirection == CameraLensDirection.front
                              ? '📷 Câmera Frontal'
                              : '📷 Câmera Traseira',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (_tirandoFoto)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      'Processando...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _tirandoFoto ? Colors.grey : const Color(0xFF4C643C),
        onPressed: _tirandoFoto ? null : () async {
          setState(() => _tirandoFoto = true);
          final image = await controller!.takePicture();

          if (mounted && !_disposed) {
            Navigator.pop(context, image.path);
          }
        },
        child: _tirandoFoto
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.camera_alt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}