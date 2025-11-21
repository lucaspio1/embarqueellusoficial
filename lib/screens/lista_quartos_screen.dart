import 'package:flutter/material.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/constants/movimentacoes.dart';

class ListaQuartosScreen extends StatefulWidget {
  const ListaQuartosScreen({super.key});

  @override
  State<ListaQuartosScreen> createState() => _ListaQuartosScreenState();
}

class _ListaQuartosScreenState extends State<ListaQuartosScreen> {
  final _db = DatabaseHelper.instance;

  bool _carregando = true;
  Map<String, List<Map<String, dynamic>>> _quartosAgrupados = {};
  String _filtroEscola = 'Todas';
  List<String> _escolas = ['Todas'];

  @override
  void initState() {
    super.initState();
    _carregarQuartos();
  }

  Future<void> _carregarQuartos() async {
    setState(() => _carregando = true);

    try {
      // Buscar quartos agrupados por número
      final quartosAgrupados = await _db.getQuartosAgrupados();

      // Para cada quarto, buscar informações de movimentação
      final Map<String, List<Map<String, dynamic>>> quartosComMovimentacao = {};
      final Set<String> escolasSet = {'Todas'};

      for (final entry in quartosAgrupados.entries) {
        final numeroQuarto = entry.key;
        final hospedes = await _db.getHospedesDoQuarto(numeroQuarto);

        // Adicionar escolas ao filtro
        for (final hospede in hospedes) {
          final escola = hospede['escola']?.toString() ?? '';
          if (escola.isNotEmpty) {
            escolasSet.add(escola);
          }
        }

        quartosComMovimentacao[numeroQuarto] = hospedes;
      }

      setState(() {
        _quartosAgrupados = quartosComMovimentacao;
        _escolas = escolasSet.toList()..sort();
        _carregando = false;
      });
    } catch (e) {
      print('❌ Erro ao carregar quartos: $e');
      setState(() => _carregando = false);
    }
  }

  /// Retorna a cor do nome baseado na movimentação
  Color _getCorMovimentacao(String? movimentacao) {
    if (movimentacao == null || movimentacao.isEmpty) {
      return Colors.grey; // Sem informação
    }

    final mov = movimentacao.trim().toUpperCase();

    // Verde: está no quarto
    if (mov == 'QUARTO' || mov == 'VOLTOU_AO_QUARTO') {
      return Colors.green.shade700;
    }

    // Vermelho: está fora do quarto
    if (mov == 'SAIU_DO_QUARTO' || mov == 'FOI_PARA_BALADA') {
      return Colors.red.shade700;
    }

    // Outras movimentações: cinza
    return Colors.grey.shade600;
  }

  /// Retorna ícone baseado na movimentação
  IconData _getIconeMovimentacao(String? movimentacao) {
    if (movimentacao == null || movimentacao.isEmpty) {
      return Icons.help_outline;
    }

    final mov = movimentacao.trim().toUpperCase();

    if (mov == 'QUARTO' || mov == 'VOLTOU_AO_QUARTO') {
      return Icons.check_circle;
    }

    if (mov == 'SAIU_DO_QUARTO') {
      return Icons.exit_to_app;
    }

    if (mov == 'FOI_PARA_BALADA') {
      return Icons.nightlife;
    }

    return Icons.help_outline;
  }

  /// Filtra quartos por escola
  Map<String, List<Map<String, dynamic>>> _filtrarQuartosPorEscola() {
    if (_filtroEscola == 'Todas') {
      return _quartosAgrupados;
    }

    final Map<String, List<Map<String, dynamic>>> filtrados = {};

    for (final entry in _quartosAgrupados.entries) {
      final hospedes = entry.value.where((h) {
        final escola = h['escola']?.toString() ?? '';
        return escola == _filtroEscola;
      }).toList();

      if (hospedes.isNotEmpty) {
        filtrados[entry.key] = hospedes;
      }
    }

    return filtrados;
  }

  @override
  Widget build(BuildContext context) {
    final quartosFiltrados = _filtrarQuartosPorEscola();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualização de Quartos'),
        backgroundColor: const Color(0xFF4C643C),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarQuartos,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filtro por escola
                if (_escolas.length > 1)
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.school, color: Color(0xFF4C643C)),
                        const SizedBox(width: 12),
                        const Text(
                          'Escola:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButton<String>(
                            value: _filtroEscola,
                            isExpanded: true,
                            items: _escolas.map((escola) {
                              return DropdownMenuItem(
                                value: escola,
                                child: Text(escola),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _filtroEscola = value;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                // Legenda
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    border: Border(
                      bottom: BorderSide(color: Colors.blue.shade200),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLegendaItem(
                        icon: Icons.check_circle,
                        color: Colors.green.shade700,
                        label: 'No Quarto',
                      ),
                      _buildLegendaItem(
                        icon: Icons.exit_to_app,
                        color: Colors.red.shade700,
                        label: 'Fora do Quarto',
                      ),
                      _buildLegendaItem(
                        icon: Icons.help_outline,
                        color: Colors.grey.shade600,
                        label: 'Sem Info',
                      ),
                    ],
                  ),
                ),

                // Lista de quartos
                Expanded(
                  child: quartosFiltrados.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.hotel_outlined,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhum quarto encontrado',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _filtroEscola == 'Todas'
                                    ? 'Sincronize os dados ou verifique a planilha'
                                    : 'Nenhum quarto para a escola $_filtroEscola',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16.0),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: quartosFiltrados.length,
                          itemBuilder: (context, index) {
                            final entry = quartosFiltrados.entries.elementAt(index);
                            final numeroQuarto = entry.key;
                            final hospedes = entry.value;

                            return _buildQuartoCard(numeroQuarto, hospedes);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildLegendaItem({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildQuartoCard(String numeroQuarto, List<Map<String, dynamic>> hospedes) {
    // Contar quantos estão no quarto vs fora
    int noQuarto = 0;
    int foraQuarto = 0;

    for (final hospede in hospedes) {
      final mov = hospede['movimentacao']?.toString().trim().toUpperCase() ?? '';
      if (mov == 'QUARTO' || mov == 'VOLTOU_AO_QUARTO') {
        noQuarto++;
      } else if (mov == 'SAIU_DO_QUARTO' || mov == 'FOI_PARA_BALADA') {
        foraQuarto++;
      }
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: const Color(0xFF4C643C).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header do quarto
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF4C643C),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.hotel, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Quarto $numeroQuarto',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildContadorBadge(
                      icon: Icons.check_circle,
                      count: noQuarto,
                      color: Colors.green.shade100,
                      textColor: Colors.green.shade900,
                    ),
                    _buildContadorBadge(
                      icon: Icons.exit_to_app,
                      count: foraQuarto,
                      color: Colors.red.shade100,
                      textColor: Colors.red.shade900,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Lista de hóspedes
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemCount: hospedes.length,
              itemBuilder: (context, index) {
                final hospede = hospedes[index];
                final nome = hospede['nome_hospede']?.toString() ?? 'Sem nome';
                final escola = hospede['escola']?.toString() ?? '';
                final movimentacao = hospede['movimentacao']?.toString();

                final cor = _getCorMovimentacao(movimentacao);
                final icone = _getIconeMovimentacao(movimentacao);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(icone, color: cor, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nome,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (escola.isNotEmpty)
                              Text(
                                escola,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContadorBadge({
    required IconData icon,
    required int count,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 14),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
