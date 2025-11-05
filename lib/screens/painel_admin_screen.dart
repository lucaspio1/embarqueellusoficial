import 'dart:async';
import 'package:flutter/material.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/auth_service.dart';
import 'package:embarqueellus/services/alunos_sync_service.dart';
import 'package:embarqueellus/services/logs_sync_service.dart';
import 'package:embarqueellus/services/user_sync_service.dart';
import 'package:embarqueellus/screens/lista_alunos_screen.dart';
import 'package:embarqueellus/screens/lista_logs_screen.dart';

class PainelAdminScreen extends StatefulWidget {
  const PainelAdminScreen({super.key});

  @override
  State<PainelAdminScreen> createState() => _PainelAdminScreenState();
}

class _PainelAdminScreenState extends State<PainelAdminScreen> {
  final _db = DatabaseHelper.instance;
  final _authService = AuthService.instance;
  final _alunosSync = AlunosSyncService.instance;
  final _logsSync = LogsSyncService.instance;
  final _userSync = UserSyncService.instance;

  bool _carregando = true;
  bool _sincronizando = false;
  int _totalAlunos = 0;
  int _totalFaciais = 0;
  int _totalLogs = 0;
  Map<String, dynamic>? _usuario;
  Map<String, int> _contagemPorLocal = {};
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _inicializar();
    _iniciarSyncAutomatico();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  /// Inicializa o painel com sincronização inicial
  Future<void> _inicializar() async {
    // Sincronizar todas as tabelas no primeiro acesso
    await _sincronizarTodasTabelas();
    // Carregar dados locais
    await _carregarDados();
  }

  /// Inicia sincronização automática a cada 10 minutos
  void _iniciarSyncAutomatico() {
    _syncTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      if (mounted) {
        _sincronizarTodasTabelas();
      }
    });
  }

  /// Sincroniza todas as tabelas do Google Sheets
  Future<void> _sincronizarTodasTabelas() async {
    if (_sincronizando) return;

    setState(() => _sincronizando = true);

    try {
      print('🔄 [PainelAdmin] Iniciando sincronização de todas as tabelas...');

      // Sincronizar usuários
      await _userSync.syncUsuariosFromSheets();

      // Sincronizar alunos
      await _alunosSync.syncAlunosFromSheets();

      // Sincronizar logs
      await _logsSync.syncLogsFromSheets();

      print('✅ [PainelAdmin] Todas as tabelas sincronizadas com sucesso');

      // Recarregar dados após sincronização
      await _carregarDados();
    } catch (e) {
      print('❌ Erro ao sincronizar tabelas: $e');
    } finally {
      if (mounted) {
        setState(() => _sincronizando = false);
      }
    }
  }

  String _formatarLocal(String valor) {
    final texto = valor.toLowerCase();
    if (texto == 'sem registro') {
      return 'Sem registro';
    }
    return texto
        .split(' ')
        .map((palavra) =>
            palavra.isEmpty ? palavra : '${palavra[0].toUpperCase()}${palavra.substring(1)}')
        .join(' ');
  }

  Future<void> _carregarDados() async {
    setState(() => _carregando = true);

    try {
      final alunos = await _db.getAllAlunos();
      final alunosComFacial = await _db.getTodosAlunosComFacial();
      final logs = await _db.getAllLogs();
      final contagemPorLocal = await _db.getContagemPorMovimentacao();
      final usuario = await _authService.getUsuarioLogado();

      setState(() {
        _totalAlunos = alunos.length;
        _totalFaciais = alunosComFacial.length;
        _totalLogs = logs.length;
        _usuario = usuario;
        _contagemPorLocal = contagemPorLocal;
        _carregando = false;
      });
    } catch (e) {
      print('❌ Erro ao carregar dados: $e');
      setState(() => _carregando = false);
    }
  }

  Future<void> _limparDados() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Limpar Todos os Dados'),
        content: const Text(
          'Isso irá apagar todos os dados locais:\n\n'
          '• Alunos\n'
          '• Passageiros\n'
          '• Faciais\n'
          '• Embeddings\n'
          '• Logs\n\n'
          'Esta ação não pode ser desfeita!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sim, Limpar Tudo'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await _db.clearAllData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Todos os dados foram limpos'),
              backgroundColor: Colors.green,
            ),
          );
          _carregarDados();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Erro ao limpar dados: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel Administrativo'),
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
              icon: const Icon(Icons.refresh),
              onPressed: _sincronizarTodasTabelas,
              tooltip: 'Sincronizar todas as tabelas',
            ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Informações do usuário
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const CircleAvatar(
                            radius: 40,
                            backgroundColor: Color(0xFF4C643C),
                            child: Icon(
                              Icons.admin_panel_settings,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _usuario?['nome'] ?? 'Administrador',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _usuario?['perfil'] ?? 'ADMIN',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Estatísticas
                  const Text(
                    'Estatísticas do Sistema',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Alunos',
                          _totalAlunos.toString(),
                          Icons.people,
                          Colors.blue,
                          onTap: _abrirListaAlunos,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Faciais',
                          _totalFaciais.toString(),
                          Icons.face,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  _buildStatCard(
                    'Logs de Reconhecimento',
                    _totalLogs.toString(),
                    Icons.history,
                    Colors.indigo,
                    onTap: _abrirListaLogs,
                  ),

                  const SizedBox(height: 24),

                  if (_contagemPorLocal.isNotEmpty) ...[
                    const Text(
                      'Distribuição por Local',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Converter entries para lista modificável
                    ...List<MapEntry<String, int>>.from(_contagemPorLocal.entries).map(
                      (entry) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.place),
                          title: Text(_formatarLocal(entry.key)),
                          trailing: Text(
                            entry.value.toString(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  if (_contagemPorLocal.isEmpty)
                    const SizedBox(height: 32)
                  else
                    const SizedBox(height: 8),

                  // Ações administrativas
                  const Text(
                    'Ações Administrativas',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  ElevatedButton.icon(
                    onPressed: _limparDados,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('LIMPAR TODOS OS DADOS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Informação
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Use essas ações com cuidado. Todas as operações são irreversíveis.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _abrirListaAlunos() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ListaAlunosScreen(),
      ),
    );
  }

  void _abrirListaLogs() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ListaLogsScreen(),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    final card = Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      );
    }

    return card;
  }
}
