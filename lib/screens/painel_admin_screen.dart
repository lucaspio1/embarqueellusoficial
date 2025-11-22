import 'dart:async';
import 'package:flutter/material.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/auth_service.dart';
import 'package:embarqueellus/services/alunos_sync_service.dart';
import 'package:embarqueellus/services/logs_sync_service.dart';
import 'package:embarqueellus/services/user_sync_service.dart';
import 'package:embarqueellus/services/acoes_criticas_service.dart';
import 'package:embarqueellus/services/quartos_sync_service.dart';
import 'package:embarqueellus/screens/lista_alunos_screen.dart';
import 'package:embarqueellus/screens/lista_logs_screen.dart';
import 'package:embarqueellus/screens/lista_quartos_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:embarqueellus/screens/lista_por_local_screen.dart';
import 'package:embarqueellus/constants/movimentacoes.dart';

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
  final _acoesCriticas = AcoesCriticasService.instance;
  final _quartosSync = QuartosSyncService.instance;

  bool _carregando = true;
  bool _sincronizando = false;
  int _totalAlunos = 0;
  int _totalFaciais = 0;
  int _totalLogs = 0;
  int _totalQuartos = 0;
  Map<String, dynamic>? _usuario;
  Map<String, int> _contagemPorLocal = {};
  Timer? _syncTimer;
  DateTime? _ultimaAtualizacao;

  @override
  void initState() {
    super.initState();
    _carregarDados();
    _carregarUltimaAtualizacao();
    _iniciarSyncAutomatico();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  /// Carrega horário da última atualização do SharedPreferences
  Future<void> _carregarUltimaAtualizacao() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getString('ultima_sincronizacao');
      if (timestamp != null && mounted) {
        setState(() {
          _ultimaAtualizacao = DateTime.parse(timestamp);
        });
      }
    } catch (e) {
      print('❌ Erro ao carregar última atualização: $e');
    }
  }

  /// Salva horário da última atualização no SharedPreferences
  Future<void> _salvarUltimaAtualizacao() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final agora = DateTime.now();
      await prefs.setString('ultima_sincronizacao', agora.toIso8601String());
      if (mounted) {
        setState(() {
          _ultimaAtualizacao = agora;
        });
      }
    } catch (e) {
      print('❌ Erro ao salvar última atualização: $e');
    }
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
    if (!mounted) return;

    setState(() => _sincronizando = true);

    try {
      print('🔄 [PainelAdmin] Iniciando sincronização de todas as tabelas...');

      // Sincronizar usuários
      await _userSync.syncUsuariosFromSheets();

      // Sincronizar alunos
      await _alunosSync.syncAlunosFromSheets();

      // Sincronizar pessoas (com embeddings e movimentação)
      await _alunosSync.syncPessoasFromSheets();

      // Sincronizar logs
      await _logsSync.syncLogsFromSheets();

      // Sincronizar quartos
      await _quartosSync.syncQuartosFromSheets();

      print('✅ [PainelAdmin] Todas as tabelas sincronizadas com sucesso');

      // Salvar horário da última atualização
      await _salvarUltimaAtualizacao();

      // Recarregar dados após sincronização
      await _carregarDados();

      // Forçar rebuild da UI
      if (mounted) {
        setState(() {});
      }

      // Mostrar mensagem de sucesso
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Dados atualizados com sucesso!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Erro ao sincronizar tabelas: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao atualizar: $e'),
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

  // =========================================================================
  // AÇÕES CRÍTICAS
  // =========================================================================

  /// Formata data ISO para formato DD/MM/YYYY
  String _formatarData(String dataIso) {
    try {
      final dateTime = DateTime.parse(dataIso);
      return DateFormat('dd/MM/yyyy').format(dateTime);
    } catch (e) {
      return dataIso; // Retorna original se não conseguir parsear
    }
  }

  /// Dialog para selecionar qual viagem encerrar
  Future<Map<String, String>?> _mostrarDialogSelecionarViagem() async {
    // Buscar viagens disponíveis
    _mostrarProgresso('Carregando viagens...');

    final viagens = await _acoesCriticas.listarViagens();

    if (Navigator.canPop(context)) Navigator.pop(context);

    if (viagens.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Nenhuma viagem encontrada'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return null;
    }

    // Mostrar dialog de seleção
    return await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.blue),
            SizedBox(width: 12),
            Text('Selecionar Viagem'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escolha qual viagem deseja encerrar:',
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              // Lista de viagens com scroll
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...viagens.map((viagem) {
                final inicio = viagem['inicio_viagem'] ?? '';
                final fim = viagem['fim_viagem'] ?? '';
                final inicioFormatado = _formatarData(inicio);
                final fimFormatado = _formatarData(fim);
                final label = '$inicioFormatado a $fimFormatado';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, viagem),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade50,
                      foregroundColor: Colors.blue.shade900,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.blue.shade200),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16),
                      ],
                    ),
                  ),
                );
                      }),
                      const Divider(height: 24),
                      // Opção: Todas as viagens
                      ElevatedButton(
                onPressed: () => Navigator.pop(context, {'todas': 'sim'}),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade900,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.delete_sweep, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'TODAS AS VIAGENS',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                        Icon(Icons.warning_amber, size: 20),
                      ],
                    ),
                  ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('CANCELAR'),
          ),
        ],
      ),
    );
  }

  /// AÇÃO CRÍTICA: Encerrar viagem (limpar todos os dados)
  Future<void> _encerrarViagem() async {
    // Confirmação 1: Verificar se é admin
    if (_usuario?['perfil']?.toString().toUpperCase() != 'ADMIN') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Apenas administradores podem encerrar viagem'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // NOVO: Selecionar viagem
    final viagemSelecionada = await _mostrarDialogSelecionarViagem();

    if (viagemSelecionada == null) {
      // Usuário cancelou
      return;
    }

    final bool todasViagens = viagemSelecionada.containsKey('todas');
    final String? inicioViagem = viagemSelecionada['inicio_viagem'];
    final String? fimViagem = viagemSelecionada['fim_viagem'];

    final String mensagemViagem = todasViagens
        ? 'TODAS AS VIAGENS'
        : '${_formatarData(inicioViagem ?? '')} a ${_formatarData(fimViagem ?? '')}';

    // Confirmação 2: Dialog de aviso (atualizado com viagem selecionada)
    final confirmacao1 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 32),
            const SizedBox(width: 12),
            const Text('ATENÇÃO'),
          ],
        ),
        content: Text(
          '⚠️ ESTA AÇÃO É IRREVERSÍVEL!\n\n'
              'Você está prestes a APAGAR ${todasViagens ? "TODOS OS DADOS" : "os dados da viagem"}:\n'
              '${todasViagens ? "" : "📅 Viagem: $mensagemViagem\n\n"}'
              '• Aba PESSOAS do Google Sheets\n'
              '• Aba LOGS do Google Sheets\n'
              '• Aba ALUNOS do Google Sheets\n'
              '• Banco de dados local do aplicativo\n\n'
              '${todasViagens ? "TODOS OS DADOS" : "Os dados desta viagem"} SERÃO PERDIDOS PERMANENTEMENTE!\n\n'
              'Deseja continuar?',
          style: const TextStyle(height: 1.5, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continuar', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );

    if (confirmacao1 != true) return;

    // Confirmação 3: Confirmação final com texto
    final confirmacao2 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('CONFIRMAÇÃO FINAL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Digite "ENCERRAR" para confirmar a exclusão ${todasViagens ? "de TODOS OS DADOS" : "da viagem"}:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            if (!todasViagens) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        mensagemViagem,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Digite ENCERRAR',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                Navigator.pop(context, value.toUpperCase() == 'ENCERRAR');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (confirmacao2 != true) return;

    // Executar ação
    _mostrarProgresso('Encerrando viagem...');

    final resultado = todasViagens
        ? await _acoesCriticas.encerrarViagem()
        : await _acoesCriticas.encerrarViagem(
            inicioViagem: inicioViagem,
            fimViagem: fimViagem,
          );

    if (Navigator.canPop(context)) Navigator.pop(context);

    if (resultado.success) {
      // Sincronizar dados do Google Sheets para atualizar o painel
      print('🔄 Sincronizando dados após encerrar viagem...');
      _mostrarProgresso('Atualizando painel...');

      await _sincronizarTodasTabelas();

      if (Navigator.canPop(context)) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${resultado.message}\n'
              '${todasViagens ? "" : "📅 Viagem: $mensagemViagem\n"}'
              '✅ Painel atualizado!'
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${resultado.message}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// AÇÃO CRÍTICA: Enviar todos para QUARTO
  Future<void> _enviarTodosParaQuarto() async {
    // Confirmação 1: Dialog de aviso
    final confirmacao = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.bed, color: Colors.blue.shade700, size: 28),
            const SizedBox(width: 12),
            const Flexible(
              child: Text(
                'Enviar Todos para Quarto',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: const Text(
          'Esta ação irá atualizar a movimentação de TODAS as pessoas para "QUARTO".\n\n'
              'Isso afeta:\n'
              '• Aba PESSOAS do Google Sheets\n'
              '• Banco de dados local\n\n'
              'Deseja continuar?',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmacao != true) return;

    // Executar ação
    _mostrarProgresso('Enviando todos para QUARTO...');

    final resultado = await _acoesCriticas.enviarTodosParaQuarto();

    if (Navigator.canPop(context)) Navigator.pop(context);

    if (resultado.success) {
      // Sincronizar dados do Google Sheets para atualizar o painel
      print('🔄 Sincronizando dados após enviar para quarto...');
      _mostrarProgresso('Atualizando painel...');

      await _sincronizarTodasTabelas();

      if (Navigator.canPop(context)) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${resultado.message}\n✅ Painel atualizado!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${resultado.message}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _mostrarProgresso(String mensagem) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(mensagem),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // CARREGAMENTO DE DADOS
  // =========================================================================

  /// Agrupa as contagens do banco de acordo com os grupos de exibição
  Map<String, int> _agruparContagens(Map<String, int> contagemBanco) {
    final Map<String, int> contagemAgrupada = {};

    // Grupo 1: NO QUARTO (QUARTO + VOLTOU_AO_QUARTO)
    final totalQuarto = (contagemBanco['QUARTO'] ?? 0) + (contagemBanco['VOLTOU_AO_QUARTO'] ?? 0);
    contagemAgrupada[Movimentacoes.grupoQuarto] = totalQuarto;

    // Grupo 2: FORA DO QUARTO (SAIU_DO_QUARTO)
    contagemAgrupada[Movimentacoes.grupoForaDoQuarto] = contagemBanco['SAIU_DO_QUARTO'] ?? 0;

    // Grupo 3: BALADA (FOI_PARA_BALADA)
    contagemAgrupada[Movimentacoes.grupoBalada] = contagemBanco['FOI_PARA_BALADA'] ?? 0;

    return contagemAgrupada;
  }

  Future<void> _carregarDados() async {
    if (!mounted) return;
    setState(() => _carregando = true);

    try {
      final alunos = await _db.getAllAlunos();
      final alunosComFacial = await _db.getTodosAlunosComFacial();
      final logs = await _db.getAllLogs();
      final quartos = await _db.getAllQuartos();
      final contagemPorLocal = await _db.getContagemPorMovimentacao();
      final usuario = await _authService.getUsuarioLogado();

      // Agrupar contagens para exibição em 3 cards
      final contagemAgrupada = _agruparContagens(contagemPorLocal);

      if (mounted) {
        setState(() {
          _totalAlunos = alunos.length;
          _totalFaciais = alunosComFacial.length;
          _totalLogs = logs.length;
          _totalQuartos = quartos.length;
          _usuario = usuario;
          _contagemPorLocal = contagemAgrupada;
          _carregando = false;
        });
      }
    } catch (e) {
      print('❌ Erro ao carregar dados: $e');
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel Administrativo'),
        backgroundColor: const Color(0xFF4C643C),
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

            // Card de Atualização
            _buildAtualizacaoCard(),

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

            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Logs',
                    _totalLogs.toString(),
                    Icons.history,
                    Colors.indigo,
                    onTap: _abrirListaLogs,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Quartos',
                    _totalQuartos.toString(),
                    Icons.hotel,
                    Colors.orange,
                    onTap: _abrirListaQuartos,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Distribuição por Local
            if (_contagemPorLocal.isNotEmpty) ...[
              const Text(
                'Distribuição por Local',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Cards clicáveis para movimentações (3 grupos)
              _buildLocalCard(Movimentacoes.grupoQuarto, _contagemPorLocal[Movimentacoes.grupoQuarto] ?? 0),
              _buildLocalCard(Movimentacoes.grupoForaDoQuarto, _contagemPorLocal[Movimentacoes.grupoForaDoQuarto] ?? 0),
              _buildLocalCard(Movimentacoes.grupoBalada, _contagemPorLocal[Movimentacoes.grupoBalada] ?? 0),

              const SizedBox(height: 24),
            ] else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Icon(Icons.location_off, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhuma movimentação registrada',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Ações Críticas
            const Text(
              'Ações Críticas',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Botão: Enviar Todos para Quarto
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _enviarTodosParaQuarto,
                icon: const Icon(Icons.bed, size: 24),
                label: const Text(
                  'ENVIAR TODOS PARA QUARTO',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Botão: Encerrar Viagem
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _encerrarViagem,
                icon: const Icon(Icons.delete_forever, size: 24),
                label: const Text(
                  'ENCERRAR VIAGEM',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Aviso sobre Encerrar Viagem
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ENCERRAR VIAGEM apaga TODOS os dados permanentemente!',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Informações
            const Text(
              'Informações',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Informação
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Os dados são sincronizados automaticamente a cada 10 minutos com o Google Sheets.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade900,
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

  void _abrirListaQuartos() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ListaQuartosScreen(),
      ),
    );
  }

  Widget _buildAtualizacaoCard() {
    final dataFormatada = _ultimaAtualizacao != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(_ultimaAtualizacao!)
        : 'Nunca';

    return Card(
      elevation: 4,
      color: const Color(0xFF4C643C),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.sync,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sincronização de Dados',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Última atualização: $dataFormatada',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _sincronizando ? null : _sincronizarTodasTabelas,
                icon: _sincronizando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF4C643C),
                        ),
                      )
                    : const Icon(Icons.cloud_download),
                label: Text(
                  _sincronizando ? 'Atualizando...' : 'ATUALIZAR DADOS',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF4C643C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Sincroniza: Usuários, Alunos, Logs e Quartos',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
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

  Widget _buildLocalCard(String local, int total) {
    final info = _getInfoLocal(local);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () {
          print('🔘 Card clicado: $local - Total: $total');
          if (total > 0) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ListaPorLocalScreen(local: local),
              ),
            ).then((_) {
              print('🔄 Retornou da lista de $local, recarregando dados...');
              _carregarDados();
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Nenhuma pessoa em ${info['titulo']}'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: info['cor'].withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  info['icone'],
                  color: info['cor'],
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info['titulo'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$total ${total == 1 ? "pessoa" : "pessoas"}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: info['cor'].withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  total.toString(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: info['cor'],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _getInfoLocal(String grupo) {
    switch (grupo.toUpperCase()) {
      case 'GRUPO_QUARTO':
        return {
          'titulo': 'No Quarto',
          'icone': Icons.bed,
          'cor': Colors.blue,
        };
      case 'SAIU_DO_QUARTO':
        return {
          'titulo': 'Fora do Quarto',
          'icone': Icons.exit_to_app,
          'cor': Colors.orange,
        };
      case 'FOI_PARA_BALADA':
        return {
          'titulo': 'Balada',
          'icone': Icons.nightlife,
          'cor': Colors.purple,
        };
      default:
        return {
          'titulo': grupo,
          'icone': Icons.place,
          'cor': Colors.grey,
        };
    }
  }
}