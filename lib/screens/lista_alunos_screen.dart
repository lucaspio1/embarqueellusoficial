import 'package:flutter/material.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/alunos_sync_service.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/firebase_service.dart';
import 'package:embarqueellus/models/camera_mode.dart';
import 'package:embarqueellus/models/face_camera_options.dart';
import 'package:embarqueellus/models/face_camera_result.dart';
import 'package:embarqueellus/screens/unified_face_camera_screen.dart';
import 'package:embarqueellus/config/app_config.dart';

class ListaAlunosScreen extends StatefulWidget {
  const ListaAlunosScreen({super.key});

  @override
  State<ListaAlunosScreen> createState() => _ListaAlunosScreenState();
}

class _ListaAlunosScreenState extends State<ListaAlunosScreen> {
  final _db = DatabaseHelper.instance;
  final _alunosSync = AlunosSyncService.instance;
  final _faceService = FaceRecognitionService.instance;

  bool _carregando = true;
  bool _sincronizando = false;
  bool _processando = false;
  List<Map<String, dynamic>> _alunos = [];
  List<Map<String, dynamic>> _alunosFiltrados = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarAlunos();
    _searchController.addListener(_filtrarAlunos);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _carregarAlunos() async {
    setState(() => _carregando = true);

    try {
      final alunos = await _db.getAllAlunos();
      setState(() {
        _alunos = alunos;
        _alunosFiltrados = alunos;
        _carregando = false;
      });
    } catch (e) {
      print('❌ Erro ao carregar alunos: $e');
      setState(() => _carregando = false);
    }
  }

  Future<void> _sincronizarAlunos() async {
    setState(() => _sincronizando = true);

    try {
      final result = await _alunosSync.syncAlunosFromSheets();

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${result.message}'),
              backgroundColor: Colors.green,
            ),
          );
          await _carregarAlunos();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${result.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao sincronizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sincronizando = false);
      }
    }
  }

  void _filtrarAlunos() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _alunosFiltrados = _alunos;
      } else {
        _alunosFiltrados = _alunos.where((aluno) {
          final nome = (aluno['nome'] ?? '').toString().toLowerCase();
          final cpf = (aluno['cpf'] ?? '').toString().toLowerCase();
          final turma = (aluno['turma'] ?? '').toString().toLowerCase();
          return nome.contains(query) || cpf.contains(query) || turma.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de Alunos'),
        backgroundColor: const Color(0xFF4C643C),
        actions: [
          IconButton(
            icon: _sincronizando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.sync),
            onPressed: _sincronizando ? null : _sincronizarAlunos,
            tooltip: 'Sincronizar',
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de pesquisa
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por nome, CPF ou turma...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),

          // Contador de resultados
          if (!_carregando)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '${_alunosFiltrados.length} aluno(s) encontrado(s)',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 14,
                    ),
                  ),
                  if (_searchController.text.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      'de ${_alunos.length} total',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Lista de alunos
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _alunosFiltrados.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
                                  ? 'Nenhum aluno cadastrado'
                                  : 'Nenhum aluno encontrado',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            if (_alunos.isEmpty) ...[
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: _sincronizarAlunos,
                                icon: const Icon(Icons.sync),
                                label: const Text('Sincronizar Alunos'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4C643C),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _alunosFiltrados.length,
                        itemBuilder: (context, index) {
                          final aluno = _alunosFiltrados[index];
                          return _buildAlunoCard(aluno);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CADASTRO FACIAL
  // =========================================================
  Future<void> _cadastrarFacial(Map<String, dynamic> aluno) async {
    try {
      final cfg = AppConfig.instance;
      // Abre tela unificada de câmera em modo de cadastro
      final result = await Navigator.push<FaceCameraResult>(
        context,
        MaterialPageRoute(
          builder: (_) => UnifiedFaceCameraScreen(
            mode: CameraMode.enrollment,
            options: FaceCameraOptions(
              useFrontCamera: cfg.useFrontCameraEnrollment,
              resolution: cfg.cameraResolutionPreset,
              showFaceGuide: cfg.showFaceGuide,
              burstCount: cfg.enrollmentBurstCount,
              burstInterval: Duration(milliseconds: cfg.enrollmentBurstIntervalMs),
              title: 'Cadastrar ${aluno['nome']}',
              subtitle: 'Posicione o rosto do aluno',
            ),
          ),
        ),
      );

      // Se cancelou ou falhou
      if (result == null || !result.success) {
        return;
      }

      setState(() => _processando = true);
      final faces = (result.processedImages != null &&
              result.processedImages!.isNotEmpty)
          ? result.processedImages!
          : [result.firstProcessedImage!];

      final embeddings = <List<double>>[];
      for (final face in faces) {
        embeddings.add(await _faceService.extractEmbedding(face));
      }
      final rawAvg = List<double>.filled(embeddings[0].length, 0.0);
      for (final emb in embeddings) {
        for (int i = 0; i < emb.length; i++) {
          rawAvg[i] += emb[i] / embeddings.length;
        }
      }
      final embedding = _faceService.normalizeL2(rawAvg);

      print('📤 [CadastroFacial] Embedding extraído (${faces.length} foto(s)): ${embedding.length} dimensões');

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

      setState(() => _processando = false);

      await _carregarAlunos();

      if (mounted) {
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
      }
    } catch (e) {
      print('❌ Erro ao cadastrar facial: $e');
      setState(() => _processando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro ao cadastrar facial: $e')),
        );
      }
    }
  }

  Future<void> _cadastrarFacialAvancado(Map<String, dynamic> aluno) async {
    try {
      final result = await Navigator.push<FaceCameraResult>(
        context,
        MaterialPageRoute(
          builder: (_) => UnifiedFaceCameraScreen(
            mode: CameraMode.enrollmentAdvanced,
            options: FaceCameraOptions(
              useFrontCamera: false,
              title: 'Cadastro Avançado - ${aluno['nome']}',
              subtitle: 'Vamos tirar 3 fotos para maior precisão',
              showCaptureCounter: true,
            ),
          ),
        ),
      );

      if (result == null || !result.success || result.processedImages == null || result.processedImages!.isEmpty) {
        return;
      }

      setState(() => _processando = true);

      final embeddings = <List<double>>[];
      for (final face in result.processedImages!) {
        final emb = await _faceService.extractEmbedding(face);
        embeddings.add(emb);
      }

      final rawAvg = List<double>.filled(embeddings[0].length, 0.0);
      for (final emb in embeddings) {
        for (int i = 0; i < emb.length; i++) {
          rawAvg[i] += emb[i] / embeddings.length;
        }
      }
      final embedding = _faceService.normalizeL2(rawAvg);

      print(
        '📤 [CadastroFacialAvançado] Embedding normalizado extraído de ${result.processedImages!.length} fotos: ${embedding.length} dimensões',
      );

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

      setState(() => _processando = false);

      await _carregarAlunos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '✅ Facial Avançada cadastrada: ${aluno['nome']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('🎯 3 fotos processadas para maior precisão'),
                const Text('☁️ Sincronizando em segundo plano...'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      print('❌ Erro no cadastro avançado: $e');
      setState(() => _processando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro no cadastro avançado: $e')),
        );
      }
    }
  }

  Widget _buildAlunoCard(Map<String, dynamic> aluno) {
    final nome = aluno['nome'] ?? 'Sem nome';
    final cpf = aluno['cpf'] ?? 'Sem CPF';
    final email = aluno['email'] ?? '';
    final telefone = aluno['telefone'] ?? '';
    final turma = aluno['turma'] ?? '';
    final facial = aluno['facial'] ?? 'NAO';
    final temQr = aluno['tem_qr'] ?? 'NAO';

    final hasFacial = aluno['facial_cadastrada'] == 1 ||
        facial.toString().toUpperCase() == 'CADASTRADA';
    final hasQr = temQr.toString().toUpperCase() == 'SIM';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nome e badges
            Row(
              children: [
                Expanded(
                  child: Text(
                    nome,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (hasFacial)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.face,
                          size: 14,
                          color: Colors.green.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Facial',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (hasQr) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.qr_code,
                          size: 14,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'QR',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 12),

            // Informações do aluno
            if (cpf.isNotEmpty && cpf != 'Sem CPF')
              _buildInfoRow(Icons.badge, 'CPF', cpf),
            if (turma.isNotEmpty)
              _buildInfoRow(Icons.class_, 'Turma', turma),
            if (email.isNotEmpty)
              _buildInfoRow(Icons.email, 'Email', email),
            if (telefone.isNotEmpty)
              _buildInfoRow(Icons.phone, 'Telefone', telefone),

            // Botão de cadastro facial em rajada (1 toque → 3 fotos automáticas)
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _processando
                    ? null
                    : () => _cadastrarFacialAvancado(aluno),
                icon: const Icon(Icons.face_retouching_natural, size: 20),
                label: Text(
                  hasFacial
                      ? 'Refazer Facial (3 fotos)'
                      : 'Cadastrar Facial (3 fotos)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      hasFacial ? Colors.orange : const Color(0xFF4C643C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
