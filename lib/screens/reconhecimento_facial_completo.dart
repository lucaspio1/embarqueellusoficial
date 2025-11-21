// lib/screens/reconhecimento_facial_completo.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/offline_sync_service.dart';
import 'package:embarqueellus/services/alunos_sync_service.dart';
import 'package:embarqueellus/services/auth_service.dart';
import 'package:embarqueellus/models/camera_mode.dart';
import 'package:embarqueellus/models/face_camera_options.dart';
import 'package:embarqueellus/models/face_camera_result.dart';
import 'package:embarqueellus/screens/unified_face_camera_screen.dart';

class ReconhecimentoFacialScreen extends StatefulWidget {
  const ReconhecimentoFacialScreen({super.key});

  @override
  State<ReconhecimentoFacialScreen> createState() => _ReconhecimentoFacialScreenState();
}

class _ReconhecimentoFacialScreenState extends State<ReconhecimentoFacialScreen> {
  final _db = DatabaseHelper.instance;
  final _faceService = FaceRecognitionService.instance;

  List<Map<String, dynamic>> _todosAlunos = [];
  List<Map<String, dynamic>> _logsHoje = [];
  bool _carregando = true;
  bool _processando = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarDados();
    FaceRecognitionService.instance.init();

  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados({bool forcarSync = false}) async {
    setState(() => _carregando = true);
    try {
      // Verificar se já existem alunos locais com facial
      final alunosLocais = await _db.getTodosAlunosComFacial();

      // Apenas sincronizar na primeira vez (quando não há dados locais) ou se forçado
      if (alunosLocais.isEmpty || forcarSync) {
        await AlunosSyncService.instance.syncPessoasFromSheets();
      }

      // ✅ FILTRO DE DATA: Buscar apenas alunos com viagem ativa (dentro do período)
      final alunos = await _db.getTodosAlunosComFacialAtivos();

      print('📅 [Reconhecimento] ${alunos.length} alunos com facial ATIVA (dentro do período de viagem)');

      // ✅ CORREÇÃO: Buscar apenas logs do operador logado
      final usuarioLogado = await AuthService.instance.getUsuarioLogado();
      final operadorNome = usuarioLogado?['nome'] ?? 'Sistema';
      final logs = await _db.getLogsHojePorOperador(operadorNome);

      setState(() {
        _todosAlunos = alunos;
        _logsHoje = logs;
        _carregando = false;
      });
    } catch (e) {
      setState(() => _carregando = false);
    }
  }

  Future<void> _iniciarReconhecimento() async {
    try {
      await Sentry.captureMessage(
        '🎯 Iniciando reconhecimento facial - Abrindo câmera unificada',
        level: SentryLevel.info,
      );

      // Usa tela unificada que já faz detecção + reconhecimento
      final result = await _abrirCameraTela(frontal: false);

      if (result == null || !result.success) {
        await Sentry.captureMessage(
          '⚠️ Usuário CANCELOU ou erro no reconhecimento',
          level: SentryLevel.warning,
        );
        return;
      }

      // Se reconheceu alguém
      if (result.recognizedPerson != null) {
        final resultado = result.recognizedPerson!;

        await Sentry.captureMessage(
          'Reconhecimento facial bem-sucedido (tela completa)',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setTag('screen', 'reconhecimento_facial_completo');
            scope.setTag('resultado', 'sucesso');
            scope.setContexts('aluno', {
              'nome': resultado['nome'],
              'cpf': resultado['cpf'],
              'confidence': result.confidenceScore,
              'distance': result.distance,
            });
          },
        );
        await _selecionarTipoAcesso(resultado);
      } else {
        // Não reconheceu
        await Sentry.captureMessage(
          'Facial não encontrada na tela de reconhecimento completo',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('screen', 'reconhecimento_facial_completo');
            scope.setTag('resultado', 'nao_reconhecido');
          },
        );
        _mostrarDialogNaoReconhecido();
      }
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro crítico no reconhecimento (tela ReconhecimentoFacialScreen)',
        }),
      );
      if (Navigator.canPop(context)) Navigator.pop(context);
      setState(() => _processando = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Erro: $e')),
      );
    }
  }

  Future<void> _abrirBuscaManual() async {
    final aluno = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _BuscaManualDialog(alunos: _todosAlunos),
    );

    if (aluno != null) {
      await _selecionarTipoAcesso(aluno);
    }
  }

  Future<void> _selecionarTipoAcesso(Map<String, dynamic> aluno) async {
    final tipo = await showDialog<String>(
      context: context,
      builder: (context) => _SelecionarTipoAcessoDialog(aluno: aluno),
    );

    if (tipo != null) {
      await _registrarPassagem(aluno, tipo);
    }
  }

  Future<void> _registrarPassagem(Map<String, dynamic> aluno, String tipo) async {
    try {
      _mostrarProgresso('Registrando passagem...');

      final timestamp = DateTime.now();

      // ✅ Usar score real de similaridade do reconhecimento facial
      // Se não houver score (busca manual), usa 0.95 como fallback
      final confidence = (aluno['similarity_score'] as double?) ?? 0.95;

      // ✅ Obter usuário logado para registrar nome do operador
      final usuarioLogado = await AuthService.instance.getUsuarioLogado();
      final operadorNome = usuarioLogado?['nome'] ?? 'Sistema';

      // ❌ REMOVIDO: insertLog() duplicado - queueLogAcesso já faz isso
      // await _db.insertLog(...)

      // ✅ ÚNICA ORIGEM DE ESCRITA: queueLogAcesso insere no DB + enfileira para sync
      await OfflineSyncService.instance.queueLogAcesso(
        cpf: aluno['cpf'],
        personName: aluno['nome'],
        timestamp: timestamp,
        confidence: confidence,
        personId: aluno['cpf'],
        tipo: tipo,
        operadorNome: operadorNome,
        colegio: aluno['colegio'] as String? ?? '',
        turma: aluno['turma'] as String? ?? '',
        inicioViagem: aluno['inicio_viagem'] as String?,
        fimViagem: aluno['fim_viagem'] as String?,
      );

      await _db.updatePessoaMovimentacao(
        (aluno['cpf'] as String? ?? '').trim(),
        tipo.toString().toUpperCase(),
      );

      // 🔄 Sincronizar embeddings em segundo plano após envio da movimentação
      AlunosSyncService.instance.syncPessoasFromSheets();

      if (Navigator.canPop(context)) Navigator.pop(context);

      await _carregarDados();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${aluno['nome']} registrado: ${_getTipoLabel(tipo)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao registrar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<FaceCameraResult?> _abrirCameraTela({bool frontal = false}) async {
    try {
      // Usa tela unificada no modo de reconhecimento
      final result = await Navigator.push<FaceCameraResult>(
        context,
        MaterialPageRoute(
          builder: (_) => UnifiedFaceCameraScreen(
            mode: CameraMode.recognition,
            options: FaceCameraOptions(
              useFrontCamera: frontal,
              title: 'Reconhecer Aluno',
              subtitle: 'Posicione o rosto do aluno',
            ),
          ),
        ),
      );

      return result;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao abrir câmera: $e')),
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final alunosComFacial = _todosAlunos.length;
    final totalPassagensHoje = _logsHoje.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reconhecimento Facial'),
        backgroundColor: const Color(0xFF4C643C),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _carregarDados(forcarSync: true),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildHeader(alunosComFacial, totalPassagensHoje),
          _buildBotoesPrincipais(),
          const Divider(height: 1),
          Expanded(child: _buildHistorico()),
        ],
      ),
    );
  }

  Widget _buildHeader(int comFacial, int passagensHoje) {
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
          const Icon(Icons.face_retouching_natural, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Sistema de Reconhecimento',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatCard('Alunos com Facial', comFacial.toString(), Icons.verified_user),
              _buildStatCard('Passagens Hoje', passagensHoje.toString(), Icons.access_time),
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
              fontSize: 24,
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

  Widget _buildBotoesPrincipais() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _processando ? null : _iniciarReconhecimento,
              icon: const Icon(Icons.camera_alt, size: 28),
              label: const Text(
                'RECONHECER\nPOR FOTO',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4C643C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _processando ? null : _abrirBuscaManual,
              icon: const Icon(Icons.search, size: 28),
              label: const Text(
                'BUSCAR\nPOR NOME',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorico() {
    if (_logsHoje.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Nenhuma passagem registrada hoje',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _logsHoje.length,
      itemBuilder: (context, index) {
        final log = _logsHoje[index];
        return _buildLogCard(log);
      },
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final tipo = log['tipo'] ?? 'desconhecido';
    final nome = log['person_name'] ?? 'Sem nome';
    final colegio = log['colegio'] ?? '';
    final turma = log['turma'] ?? '';
    final operador = log['operador_nome'] ?? 'Sistema';
    final timestamp = DateTime.parse(log['timestamp'] ?? DateTime.now().toIso8601String());
    final hora = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

    final tipoInfo = _getTipoInfo(tipo);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tipoInfo['color'].withOpacity(0.2),
          child: Icon(tipoInfo['icon'], color: tipoInfo['color']),
        ),
        title: Text(
          nome,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tipoInfo['label']),
            const SizedBox(height: 2),
            if (colegio.isNotEmpty || turma.isNotEmpty)
              Text(
                '${colegio.isNotEmpty ? colegio : ''}${colegio.isNotEmpty && turma.isNotEmpty ? ' - ' : ''}${turma.isNotEmpty ? turma : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (colegio.isNotEmpty || turma.isNotEmpty)
              const SizedBox(height: 2),
            Text(
              'Registrado por: $operador',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            hora,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  String _getTipoLabel(String tipo) {
    return _getTipoInfo(tipo)['label'];
  }

  Map<String, dynamic> _getTipoInfo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'quarto':
      case 'voltou_ao_quarto':
        return {
          'label': 'Voltou ao Quarto',
          'icon': Icons.bed,
          'color': Colors.blue,
        };
      case 'saiu_do_quarto':
        return {
          'label': 'Saiu do Quarto',
          'icon': Icons.exit_to_app,
          'color': Colors.orange,
        };
      case 'balada':
      case 'foi_para_balada':
        return {
          'label': 'Foi para Balada',
          'icon': Icons.nightlife,
          'color': Colors.purple,
        };
      case 'embarque':
      case 'embarque_registrado':
        return {
          'label': 'Embarque Registrado',
          'icon': Icons.login,
          'color': Colors.green,
        };
      default:
        return {
          'label': 'Outro Local',
          'icon': Icons.place,
          'color': Colors.grey,
        };
    }
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

  void _mostrarDialogNaoReconhecido() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 12),
            const Text('Não Reconhecido'),
          ],
        ),
        content: const Text(
          'Aluno não encontrado no banco de dados.\n\n'
              'Você pode:\n'
              '• Tentar novamente com melhor iluminação\n'
              '• Buscar manualmente pelo nome',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _abrirBuscaManual();
            },
            child: const Text(
              'Buscar por Nome',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _iniciarReconhecimento();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4C643C),
            ),
            child: const Text('Tentar Novamente'),
          ),
        ],
      ),
    );
  }
}

class _BuscaManualDialog extends StatefulWidget {
  final List<Map<String, dynamic>> alunos;

  const _BuscaManualDialog({required this.alunos});

  @override
  State<_BuscaManualDialog> createState() => _BuscaManualDialogState();
}

class _BuscaManualDialogState extends State<_BuscaManualDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _alunosFiltrados = [];

  @override
  void initState() {
    super.initState();
    _alunosFiltrados = widget.alunos;
    _searchController.addListener(_filtrar);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filtrar() {
    final termo = _searchController.text.toLowerCase();
    setState(() {
      _alunosFiltrados = widget.alunos.where((aluno) {
        final nome = (aluno['nome'] ?? '').toLowerCase();
        final cpf = (aluno['cpf'] ?? '').toLowerCase();
        return nome.contains(termo) || cpf.contains(termo);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.search, color: Color(0xFF4C643C), size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Buscar Aluno',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nome ou CPF',
                prefixIcon: const Icon(Icons.person_search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: _alunosFiltrados.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhum aluno encontrado',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: _alunosFiltrados.length,
                itemBuilder: (context, index) {
                  final aluno = _alunosFiltrados[index];
                  final temFacial =
                      (aluno['facial'] ?? '').toString().toUpperCase() ==
                          'CADASTRADA';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: temFacial
                            ? Colors.green.shade100
                            : Colors.orange.shade100,
                        child: Icon(
                          temFacial ? Icons.face : Icons.face_retouching_off,
                          color: temFacial
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                      title: Text(
                        aluno['nome'] ?? 'Sem nome',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('CPF: ${aluno['cpf'] ?? '--'}'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => Navigator.pop(context, aluno),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelecionarTipoAcessoDialog extends StatelessWidget {
  final Map<String, dynamic> aluno;

  const _SelecionarTipoAcessoDialog({required this.aluno});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.green.shade100,
              child: Icon(
                Icons.check_circle,
                size: 48,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              aluno['nome'] ?? 'Aluno',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'CPF: ${aluno['cpf'] ?? '--'}',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            if (aluno['colegio'] != null && aluno['colegio'].toString().isNotEmpty)
              Text(
                'Colégio: ${aluno['colegio']}',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            const SizedBox(height: 4),
            if (aluno['turma'] != null && aluno['turma'].toString().isNotEmpty)
              Text(
                'Turma: ${aluno['turma']}',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Para onde o aluno está indo?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),

            _buildTipoTile(
              context,
              'Saiu do Quarto',
              Icons.exit_to_app,
              Colors.orange,
              'SAIU_DO_QUARTO',
            ),
            _buildTipoTile(
              context,
              'Voltou ao Quarto',
              Icons.home,
              Colors.green,
              'VOLTOU_AO_QUARTO',
            ),
            _buildTipoTile(
              context,
              'Foi para Balada',
              Icons.nightlife,
              Colors.purple,
              'FOI_PARA_BALADA',
            ),

            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipoTile(
      BuildContext context,
      String label,
      IconData icon,
      Color color,
      String tipo,
      ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.pop(context, tipo),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: color.withOpacity(0.9),
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}