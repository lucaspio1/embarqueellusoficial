import 'package:flutter/material.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/constants/movimentacoes.dart';

class ListaPorLocalScreen extends StatefulWidget {
  final String local;

  const ListaPorLocalScreen({
    super.key,
    required this.local,
  });

  @override
  State<ListaPorLocalScreen> createState() => _ListaPorLocalScreenState();
}

class _ListaPorLocalScreenState extends State<ListaPorLocalScreen> {
  final _db = DatabaseHelper.instance;

  bool _carregando = true;
  List<Map<String, dynamic>> _pessoas = [];
  List<Map<String, dynamic>> _pessoasFiltradas = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarPessoas();
    _searchController.addListener(_filtrarPessoas);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _carregarPessoas() async {
    setState(() => _carregando = true);

    try {
      final db = await _db.database;

      // Obter movimentações do grupo
      final movimentacoes = Movimentacoes.getMovimentacoesDoGrupo(widget.local);

      if (movimentacoes.isEmpty) {
        setState(() {
          _pessoas = [];
          _pessoasFiltradas = [];
          _carregando = false;
        });
        return;
      }

      // Criar placeholders para o IN (?, ?, ...)
      final placeholders = List.filled(movimentacoes.length, '?').join(', ');

      // Criar lista de argumentos (movimentacoes para logs + movimentacoes para WHERE IN)
      final args = [...movimentacoes.map((m) => m.toUpperCase()), ...movimentacoes.map((m) => m.toUpperCase())];

      // Buscar pessoas que estão no local/grupo específico
      final result = await db.rawQuery('''
        SELECT DISTINCT p.cpf, p.nome, p.email, p.telefone, p.turma, p.movimentacao,
               l.timestamp, l.operador_nome
        FROM pessoas_facial p
        LEFT JOIN (
          SELECT cpf, timestamp, operador_nome, tipo
          FROM logs
          WHERE tipo IN ($placeholders)
          ORDER BY timestamp DESC
        ) l ON p.cpf = l.cpf
        WHERE UPPER(TRIM(p.movimentacao)) IN ($placeholders)
        ORDER BY p.nome
      ''', args);

      setState(() {
        _pessoas = result;
        _pessoasFiltradas = result;
        _carregando = false;
      });
    } catch (e) {
      print('❌ Erro ao carregar pessoas: $e');
      setState(() => _carregando = false);
    }
  }

  void _filtrarPessoas() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _pessoasFiltradas = _pessoas;
      } else {
        _pessoasFiltradas = _pessoas.where((pessoa) {
          final nome = (pessoa['nome'] ?? '').toString().toLowerCase();
          final cpf = (pessoa['cpf'] ?? '').toString().toLowerCase();
          final turma = (pessoa['turma'] ?? '').toString().toLowerCase();
          return nome.contains(query) || cpf.contains(query) || turma.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _getInfoLocal(widget.local);

    return Scaffold(
      appBar: AppBar(
        title: Text(info['titulo']!),
        backgroundColor: info['cor'] as Color,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarPessoas,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          // Header com estatísticas
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  info['cor'] as Color,
                  (info['cor'] as Color).withOpacity(0.7),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  info['icone'] as IconData,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  info['titulo']!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        '${_pessoas.length} ${_pessoas.length == 1 ? "pessoa" : "pessoas"}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

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
                    '${_pessoasFiltradas.length} ${_pessoasFiltradas.length == 1 ? "pessoa encontrada" : "pessoas encontradas"}',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 14,
                    ),
                  ),
                  if (_searchController.text.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      'de ${_pessoas.length} total',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Lista de pessoas
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _pessoasFiltradas.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    info['icone'] as IconData,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _searchController.text.isEmpty
                        ? 'Nenhuma pessoa no ${info['titulo']}'
                        : 'Nenhuma pessoa encontrada',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pessoasFiltradas.length,
              itemBuilder: (context, index) {
                final pessoa = _pessoasFiltradas[index];
                return _buildPessoaCard(pessoa, info);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPessoaCard(Map<String, dynamic> pessoa, Map<String, dynamic> info) {
    final nome = pessoa['nome'] ?? 'Sem nome';
    final cpf = pessoa['cpf'] ?? 'Sem CPF';
    final email = pessoa['email'] ?? '';
    final telefone = pessoa['telefone'] ?? '';
    final turma = pessoa['turma'] ?? '';
    final timestamp = pessoa['timestamp']?.toString();
    final operador = pessoa['operador_nome'] ?? '';

    String horarioEntrada = 'Horário não registrado';
    if (timestamp != null && timestamp.isNotEmpty) {
      try {
        final dt = DateTime.parse(timestamp);
        horarioEntrada = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        horarioEntrada = 'Horário inválido';
      }
    }

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
            // Nome e ícone
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: (info['cor'] as Color).withOpacity(0.2),
                  child: Icon(
                    info['icone'] as IconData,
                    color: info['cor'] as Color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    nome,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Informações da pessoa
            if (cpf.isNotEmpty && cpf != 'Sem CPF')
              _buildInfoRow(Icons.badge, 'CPF', cpf),
            if (turma.isNotEmpty)
              _buildInfoRow(Icons.class_, 'Turma', turma),
            if (email.isNotEmpty)
              _buildInfoRow(Icons.email, 'Email', email),
            if (telefone.isNotEmpty)
              _buildInfoRow(Icons.phone, 'Telefone', telefone),

            const Divider(height: 24),

            // Informações de entrada
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    horarioEntrada,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),

            if (operador.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Registrado por: $operador',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],
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