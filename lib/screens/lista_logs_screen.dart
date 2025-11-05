import 'package:flutter/material.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/logs_sync_service.dart';
import 'package:intl/intl.dart';

class ListaLogsScreen extends StatefulWidget {
  const ListaLogsScreen({super.key});

  @override
  State<ListaLogsScreen> createState() => _ListaLogsScreenState();
}

class _ListaLogsScreenState extends State<ListaLogsScreen> {
  final _db = DatabaseHelper.instance;
  final _logsSync = LogsSyncService.instance;

  bool _carregando = true;
  bool _sincronizando = false;
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _logsFiltrados = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarLogs();
    _searchController.addListener(_filtrarLogs);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _carregarLogs() async {
    setState(() => _carregando = true);

    try {
      final logsFromDb = await _db.getAllLogs();

      print('🔍 [DEBUG] Total de logs carregados: ${logsFromDb.length}');

      // Criar uma cópia modificável da lista para poder ordenar
      final logs = List<Map<String, dynamic>>.from(logsFromDb);

      // Ordenar logs por timestamp (mais recentes primeiro)
      logs.sort((a, b) {
        final timestampA = a['timestamp']?.toString() ?? '';
        final timestampB = b['timestamp']?.toString() ?? '';
        return timestampB.compareTo(timestampA);
      });

      setState(() {
        _logs = logs;
        _logsFiltrados = logs;
        _carregando = false;
      });

      print('✅ [DEBUG] Logs carregados e estado atualizado. _logsFiltrados.length = ${_logsFiltrados.length}');
    } catch (e) {
      print('❌ Erro ao carregar logs: $e');
      setState(() => _carregando = false);
    }
  }

  Future<void> _sincronizarLogs() async {
    setState(() => _sincronizando = true);

    try {
      final result = await _logsSync.syncLogsFromSheets();

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${result.message}'),
              backgroundColor: Colors.green,
            ),
          );
          await _carregarLogs();
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

  void _filtrarLogs() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _logsFiltrados = _logs;
      } else {
        _logsFiltrados = _logs.where((log) {
          final nome = (log['person_name'] ?? '').toString().toLowerCase();
          final cpf = (log['cpf'] ?? '').toString().toLowerCase();
          final tipo = (log['tipo'] ?? '').toString().toLowerCase();
          final operador = (log['operador_nome'] ?? '').toString().toLowerCase();
          return nome.contains(query) || cpf.contains(query) || tipo.contains(query) || operador.contains(query);
        }).toList();
      }
    });
  }

  String _formatarData(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return 'Data não disponível';

    try {
      final dateTime = DateTime.parse(timestamp);
      return DateFormat('dd/MM/yyyy HH:mm:ss').format(dateTime);
    } catch (e) {
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🎨 [DEBUG] Build chamado - Carregando: $_carregando, Logs Filtrados: ${_logsFiltrados.length}');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs de Reconhecimento'),
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
            onPressed: _sincronizando ? null : _sincronizarLogs,
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
                hintText: 'Buscar por nome, CPF, tipo ou operador...',
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
                    '${_logsFiltrados.length} log(s) encontrado(s)',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 14,
                    ),
                  ),
                  if (_searchController.text.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      'de ${_logs.length} total',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Lista de logs
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _logsFiltrados.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
                                  ? 'Nenhum log encontrado'
                                  : 'Nenhum log encontrado para a busca',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            if (_logs.isEmpty) ...[
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: _sincronizarLogs,
                                icon: const Icon(Icons.sync),
                                label: const Text('Sincronizar Logs'),
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
                        itemCount: _logsFiltrados.length,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemBuilder: (context, index) {
                          print('🏗️ [DEBUG] Construindo card para log index $index de ${_logsFiltrados.length}');
                          final log = _logsFiltrados[index];
                          final card = _buildLogCard(log);
                          print('✅ [DEBUG] Card construído para index $index');
                          return card;
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    print('📋 [DEBUG] Construindo card para: ${log['person_name']} - Tipo: ${log['tipo']}');
    final nome = log['person_name'] ?? 'Sem nome';
    final cpf = log['cpf'] ?? 'Sem CPF';
    final timestamp = log['timestamp']?.toString() ?? '';
    final confidence = (log['confidence'] ?? 0.0).toDouble();
    final tipo = log['tipo'] ?? 'FACIAL';
    final operadorNome = log['operador_nome'] ?? 'Não registrado';

    print('📊 [DEBUG] Dados do log - Nome: $nome, CPF: $cpf, Tipo: $tipo, Timestamp: $timestamp');

    // Definir cor baseada no tipo
    Color tipoColor;
    IconData tipoIcon;

    switch (tipo.toUpperCase()) {
      case 'EMBARQUE':
        tipoColor = Colors.blue;
        tipoIcon = Icons.directions_bus;
        break;
      case 'RETORNO':
        tipoColor = Colors.orange;
        tipoIcon = Icons.home;
        break;
      case 'FACIAL':
      default:
        tipoColor = Colors.green;
        tipoIcon = Icons.face;
        break;
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      child: Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nome e tipo
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: tipoColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tipoColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tipoIcon,
                        size: 14,
                        color: tipoColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tipo.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          color: tipoColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Informações do log
            _buildInfoRow(Icons.badge, 'CPF', cpf),
            _buildInfoRow(Icons.access_time, 'Data/Hora', _formatarData(timestamp)),
            _buildInfoRow(Icons.person_outline, 'Operador', operadorNome),

            // Confidence (apenas para tipo FACIAL)
            if (tipo.toUpperCase() == 'FACIAL')
              _buildInfoRow(
                Icons.percent,
                'Confiança',
                '${(confidence * 100).toStringAsFixed(1)}%',
              ),
          ],
        ),
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
