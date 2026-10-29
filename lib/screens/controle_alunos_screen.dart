// lib/screens/controle_alunos_screen.dart
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/firebase_service.dart';
import 'package:embarqueellus/services/data_service.dart';
import 'package:embarqueellus/models/camera_mode.dart';
import 'package:embarqueellus/models/face_camera_options.dart';
import 'package:embarqueellus/models/face_camera_result.dart';
import 'package:embarqueellus/screens/unified_face_camera_screen.dart';

class ControleAlunosScreen extends StatefulWidget {
  const ControleAlunosScreen({super.key});

  @override
  State<ControleAlunosScreen> createState() => _ControleAlunosScreenState();
}

class _ControleAlunosScreenState extends State<ControleAlunosScreen> {
  final _db = DatabaseHelper.instance;
  final _faceService = FaceRecognitionService.instance;
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

      // ✅ Converter passageiros para formato de alunos
      final alunos = passageiros.map((p) {
        return {
          'cpf': p.cpf ?? '',
          'nome': p.nome,
          'colegio': p.colegio ?? '', // ✅ NOVO CAMPO
          'turma': p.turma,
          'email': '', // Passageiros não têm email, mas mantemos a estrutura
          'telefone': '',
          'inicio_viagem': p.inicioViagem ?? '',
          'fim_viagem': p.fimViagem ?? '',
        };
      }).where((a) => a['cpf']?.toString().isNotEmpty ?? false).toList();

      // ✅ CORREÇÃO: Verificar quais alunos DESTA LISTA já têm facial cadastrada
      // Não buscar TODAS as faciais do banco (que incluem outras viagens)
      final cpfsDosPassageiros = alunos
          .map((a) => a['cpf']?.toString() ?? '')
          .where((cpf) => cpf.isNotEmpty)
          .toList();

      final pessoasComFacial = await _db.getPessoasFaciaisPorCPFs(cpfsDosPassageiros);
      final cpfsComFacial = <String, bool>{};
      for (final pessoa in pessoasComFacial) {
        final cpf = pessoa['cpf']?.toString() ?? '';
        if (cpf.isNotEmpty) {
          cpfsComFacial[cpf] = true;
        }
      }

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

  Future<void> _cadastrarFacial(Map<String, dynamic> aluno) async {
    try {
      // Abre tela unificada de câmera em modo de cadastro
      final result = await Navigator.push<FaceCameraResult>(
        context,
        MaterialPageRoute(
          builder: (_) => UnifiedFaceCameraScreen(
            mode: CameraMode.enrollment,
            options: FaceCameraOptions(
              useFrontCamera: false, // Câmera traseira para melhor qualidade
              title: 'Cadastrar ${aluno['nome']}',
              subtitle: 'Posicione o rosto no centro',
            ),
          ),
        ),
      );

      // Se cancelou ou erro
      if (result == null || !result.success) return;

      setState(() => _processando = true);
      _mostrarProgresso('Extraindo características faciais...');

      // Extrair embedding da imagem processada
      final embedding = await _faceService.extractEmbedding(result.firstProcessedImage!);

      print('📤 [CadastroFacial] Embedding extraído: ${embedding.length} dimensões');

      await FirebaseService.instance.queueCadastroFacial(
        cpf: aluno['cpf'],
        nome: aluno['nome'],
        colegio: aluno['colegio'] ?? '',
        turma: aluno['turma'] ?? '',
        email: aluno['email'] ?? '',
        telefone: aluno['telefone'] ?? '',
        embedding: embedding,
        personId: aluno['cpf'],
        inicioViagem: aluno['inicio_viagem'] ?? '',
        fimViagem: aluno['fim_viagem'] ?? '',
      );

      print('✅ [CadastroFacial] Salvo localmente e enfileirado para sincronização via API');

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
      // Abre tela unificada em modo avançado (3 fotos)
      final result = await Navigator.push<FaceCameraResult>(
        context,
        MaterialPageRoute(
          builder: (_) => UnifiedFaceCameraScreen(
            mode: CameraMode.enrollmentAdvanced,
            options: FaceCameraOptions(
              useFrontCamera: false, // Câmera traseira para melhor qualidade
              title: 'Cadastro Avançado - ${aluno['nome']}',
              subtitle: 'Vamos tirar 3 fotos para maior precisão',
              showCaptureCounter: true,
            ),
          ),
        ),
      );

      // Se cancelou ou erro
      if (result == null || !result.success) return;

      setState(() => _processando = true);
      _mostrarProgresso('Processando ${result.processedImages!.length} imagens...');

      // Extrair embeddings de todas as imagens
      final embeddings = <List<double>>[];
      for (final face in result.processedImages!) {
        final emb = await _faceService.extractEmbedding(face);
        embeddings.add(emb);
      }

      // Fazer média dos embeddings e normalizar (L2) para manter norma unitária
      final rawAvg = List<double>.filled(embeddings[0].length, 0.0);
      for (final emb in embeddings) {
        for (int i = 0; i < emb.length; i++) {
          rawAvg[i] += emb[i] / embeddings.length;
        }
      }
      final embedding = _faceService.normalizeL2(rawAvg);

      print('📤 [CadastroFacialAvançado] Embedding normalizado extraído de ${result.processedImages!.length} fotos: ${embedding.length} dimensões');

      await FirebaseService.instance.queueCadastroFacial(
        cpf: aluno['cpf'],
        nome: aluno['nome'],
        colegio: aluno['colegio'] ?? '',
        turma: aluno['turma'] ?? '',
        email: aluno['email'] ?? '',
        telefone: aluno['telefone'] ?? '',
        embedding: embedding,
        personId: aluno['cpf'],
        inicioViagem: aluno['inicio_viagem'] ?? '',
        fimViagem: aluno['fim_viagem'] ?? '',
      );

      print('✅ [CadastroFacialAvançado] Salvo localmente e enfileirado para sincronização via API');

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
            'fotos_processadas': result.processedImages!.length,
          });
        },
      );

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
              Text('${aluno['nome']} - ${result.processedImages!.length} imagens processadas'),
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
