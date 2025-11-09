// lib/screens/controle_alunos_screen.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/face_image_processor.dart';
import 'package:embarqueellus/services/alunos_sync_service.dart';
import 'package:embarqueellus/services/offline_sync_service.dart';
import 'package:embarqueellus/services/face_detection_service.dart';
import 'package:embarqueellus/services/data_service.dart';
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
  List<Map<String, dynamic>> _alunosFiltrados = [];
  Map<String, bool> _alunosComFacial = {}; // Mapa CPF -> tem facial
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
    await _carregarAlunos();
  }

  Future<void> _carregarAlunos() async {
    setState(() => _carregando = true);
    try {
      // ✅ CORREÇÃO: Carregar TODOS os passageiros da lista de embarque
      await DataService().loadLocalData(
        (await SharedPreferences.getInstance()).getString('nome_aba') ?? '',
        (await SharedPreferences.getInstance()).getString('numero_onibus') ?? '',
      );

      final passageiros = DataService().passageirosEmbarque.value;

      // ✅ Verificar quais alunos JÁ TÊM facial cadastrada
      final pessoasComFacial = await _db.getAllPessoasFacial();
      final cpfsComFacial = <String, bool>{};
      for (final pessoa in pessoasComFacial) {
        final cpf = pessoa['cpf']?.toString() ?? '';
        if (cpf.isNotEmpty) {
          cpfsComFacial[cpf] = true;
        }
      }

      // ✅ Converter passageiros para formato de alunos
      final alunos = passageiros.map((p) {
        return {
          'cpf': p.cpf ?? '',
          'nome': p.nome,
          'turma': p.turma,
          'email': '', // Passageiros não têm email, mas mantemos a estrutura
          'telefone': '',
          'inicio_viagem': p.inicioViagem ?? '',
          'fim_viagem': p.fimViagem ?? '',
        };
      }).where((a) => a['cpf']?.toString().isNotEmpty ?? false).toList();

      setState(() {
        _todosAlunos = alunos;
        _alunosFiltrados = alunos;
        _alunosComFacial = cpfsComFacial;
        _carregando = false;
      });

      print('📋 ${_todosAlunos.length} alunos carregados da lista de embarque');
      print('✅ ${cpfsComFacial.length} alunos com facial cadastrada');
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
                Text('Sincronizando lista de embarque...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      // Recarrega a lista de embarque do servidor
      final prefs = await SharedPreferences.getInstance();
      final nomeAba = prefs.getString('nome_aba') ?? '';
      final numeroOnibus = prefs.getString('numero_onibus') ?? '';

      if (nomeAba.isNotEmpty && numeroOnibus.isNotEmpty) {
        await DataService().fetchData(nomeAba, onibus: numeroOnibus);
        await _carregarAlunos();

        await Sentry.captureMessage(
          'Lista de embarque sincronizada com sucesso',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setTag('screen', 'controle_alunos');
            scope.setTag('sync_type', 'lista_embarque');
            scope.setContexts('sync_stats', {
              'total_alunos': _todosAlunos.length,
              'alunos_com_facial': _alunosComFacial.length,
              'nome_aba': nomeAba,
              'numero_onibus': numeroOnibus,
            });
          },
        );

        if (mounted && mostrarMensagem) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${_todosAlunos.length} alunos sincronizados'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted && mostrarMensagem) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Nenhuma lista de embarque carregada'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('❌ [ControleAlunos] Erro ao sincronizar: $e');

      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao sincronizar lista de embarque',
          'screen': 'controle_alunos',
        }),
      );

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

      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await FaceDetectionService.instance.detect(inputImage);

      if (faces.isEmpty) {
        await Sentry.captureMessage(
          'Nenhum rosto detectado no cadastro facial',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('screen', 'controle_alunos');
            scope.setTag('error_type', 'no_face_detected');
            scope.setContexts('aluno', {
              'cpf': aluno['cpf'],
              'nome': aluno['nome'],
            });
          },
        );

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
        await Sentry.captureMessage(
          'Múltiplos rostos detectados no cadastro facial',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('screen', 'controle_alunos');
            scope.setTag('error_type', 'multiple_faces');
            scope.setContexts('aluno', {
              'cpf': aluno['cpf'],
              'nome': aluno['nome'],
              'faces_count': faces.length,
            });
          },
        );

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

      final embedding = await _faceService.extractEmbedding(processedImage);

      print('📤 [CadastroFacial] Embedding extraído: ${embedding.length} dimensões');

      await _db.upsertPessoaFacial({
        'cpf': aluno['cpf'],
        'nome': aluno['nome'],
        'email': aluno['email'] ?? '',
        'telefone': aluno['telefone'] ?? '',
        'turma': aluno['turma'] ?? '',
        'embedding': jsonEncode(embedding),
        'facial_status': 'CADASTRADA',
        'movimentacao': 'QUARTO',
        'inicio_viagem': aluno['inicio_viagem'] ?? '',
        'fim_viagem': aluno['fim_viagem'] ?? '',
      });

      print('✅ [CadastroFacial] Salvo na tabela pessoas_facial com movimentação QUARTO');

      await Sentry.captureMessage(
        'Facial cadastrada com sucesso',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('screen', 'controle_alunos');
          scope.setTag('tipo_cadastro', 'simples');
          scope.setContexts('aluno', {
            'cpf': aluno['cpf'],
            'nome': aluno['nome'],
            'embedding_dimensions': embedding.length,
          });
        },
      );

      await OfflineSyncService.instance.queueCadastroFacial(
        cpf: aluno['cpf'],
        nome: aluno['nome'],
        email: aluno['email'] ?? '',
        telefone: aluno['telefone'] ?? '',
        embedding: embedding,
        personId: aluno['cpf'],
        inicioViagem: aluno['inicio_viagem'] ?? '',
        fimViagem: aluno['fim_viagem'] ?? '',
      );

      print('✅ [CadastroFacial] Embedding enfileirado para sincronização com aba Pessoas');

      OfflineSyncService.instance.trySyncInBackground();
      print('🔄 [CadastroFacial] Sincronização em background iniciada');

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
              Text('🏠 Local inicial: QUARTO'),
              Text('☁️ Sincronizando em segundo plano...'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e, stackTrace) {
      print('❌ Erro ao cadastrar facial: $e');

      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao cadastrar facial (cadastro simples)',
          'aluno_cpf': aluno['cpf'],
          'aluno_nome': aluno['nome'],
        }),
      );

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
          continue;
        }

        if (detectedFaces.length > 1) {
          if (Navigator.canPop(context)) Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Múltiplos rostos detectados na captura $i. Tente novamente.'),
              backgroundColor: Colors.orange,
            ),
          );
          continue;
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

      final embeddings = <List<double>>[];
      for (final face in faces) {
        final emb = await _faceService.extractEmbedding(face);
        embeddings.add(emb);
      }

      final embedding = List<double>.filled(embeddings[0].length, 0.0);
      for (final emb in embeddings) {
        for (int i = 0; i < emb.length; i++) {
          embedding[i] += emb[i] / embeddings.length;
        }
      }

      print('📤 [CadastroFacialAvançado] Embedding extraído de ${faces.length} fotos: ${embedding.length} dimensões');

      await _db.upsertPessoaFacial({
        'cpf': aluno['cpf'],
        'nome': aluno['nome'],
        'email': aluno['email'] ?? '',
        'telefone': aluno['telefone'] ?? '',
        'turma': aluno['turma'] ?? '',
        'embedding': jsonEncode(embedding),
        'facial_status': 'CADASTRADA',
        'movimentacao': 'QUARTO',
        'inicio_viagem': aluno['inicio_viagem'] ?? '',
        'fim_viagem': aluno['fim_viagem'] ?? '',
      });

      print('✅ [CadastroFacialAvançado] Salvo na tabela pessoas_facial com movimentação QUARTO');

      await Sentry.captureMessage(
        'Facial avançada cadastrada com sucesso',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('screen', 'controle_alunos');
          scope.setTag('tipo_cadastro', 'avancado');
          scope.setContexts('aluno', {
            'cpf': aluno['cpf'],
            'nome': aluno['nome'],
            'embedding_dimensions': embedding.length,
            'fotos_processadas': faces.length,
          });
        },
      );

      await OfflineSyncService.instance.queueCadastroFacial(
        cpf: aluno['cpf'],
        nome: aluno['nome'],
        email: aluno['email'] ?? '',
        telefone: aluno['telefone'] ?? '',
        embedding: embedding,
        personId: aluno['cpf'],
        inicioViagem: aluno['inicio_viagem'] ?? '',
        fimViagem: aluno['fim_viagem'] ?? '',
      );

      print('✅ [CadastroFacialAvançado] Embedding enfileirado para sincronização com aba Pessoas');

      OfflineSyncService.instance.trySyncInBackground();
      print('🔄 [CadastroFacialAvançado] Sincronização em background iniciada');

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
              Text('🏠 Local inicial: QUARTO'),
              Text('☁️ Sincronizando em segundo plano...'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e, stackTrace) {
      print('❌ Erro ao cadastrar facial avançada: $e');

      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao cadastrar facial (cadastro avançado - 3 fotos)',
          'aluno_cpf': aluno['cpf'],
          'aluno_nome': aluno['nome'],
        }),
      );

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

    final totalComFacial = _alunosComFacial.length;

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
              tooltip: 'Sincronizar lista de embarque',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarAlunos,
            tooltip: 'Atualizar',
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
                    'Carregue a lista de embarque primeiro',
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
                  final cpf = aluno['cpf']?.toString() ?? '';
                  final temFacial = _alunosComFacial[cpf] ?? false;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: temFacial
                            ? Colors.green.shade100
                            : Colors.grey.shade200,
                        child: Icon(
                          temFacial
                              ? Icons.verified_user
                              : Icons.face_retouching_off,
                          color: temFacial
                              ? Colors.green.shade700
                              : Colors.grey.shade600,
                        ),
                      ),
                      title: Text(aluno['nome'] ?? 'Sem nome'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CPF: ${cpf.isEmpty ? "--" : cpf}'),
                          if (aluno['turma'] != null &&
                              aluno['turma'].toString().isNotEmpty)
                            Text('Turma: ${aluno['turma']}'),
                          if (temFacial)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.green.shade200,
                                ),
                              ),
                              child: Text(
                                '✅ Facial cadastrada',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
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
                                Text(temFacial
                                    ? 'Refazer Simples'
                                    : 'Cadastro Simples'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'avancado',
                            child: Row(
                              children: [
                                Icon(Icons.verified_user,
                                    color: Colors.green),
                                SizedBox(width: 8),
                                Text(temFacial
                                    ? 'Refazer Avançado'
                                    : 'Cadastro Avançado (3 fotos)'),
                              ],
                            ),
                          ),
                        ],
                        child: ElevatedButton(
                          onPressed: () => _cadastrarFacial(aluno),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: temFacial
                                ? Colors.orange
                                : const Color(0xFF4C643C),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

// ============================================================================
// CAMERA PREVIEW SCREEN
// ============================================================================

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
          Center(
            child: Container(
              width: 280,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(180),
                border: Border.all(
                  color: Colors.white.withOpacity(0.7),
                  width: 2,
                ),
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
                      if (_cameras.length > 1) const SizedBox(height: 4),
                      if (_cameras.length > 1)
                        Text(
                          _cameras[_currentCameraIndex].lensDirection ==
                              CameraLensDirection.front
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
        onPressed: _tirandoFoto
            ? null
            : () async {
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