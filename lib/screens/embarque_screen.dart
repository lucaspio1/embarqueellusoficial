import 'package:flutter/material.dart';
import 'package:embarqueellus/models/passageiro.dart';
import 'package:embarqueellus/services/data_service.dart';

class EmbarqueScreen extends StatefulWidget {
  final String colegio;
  final String onibus;
  final int totalAlunos;

  const EmbarqueScreen({
    required this.colegio,
    required this.onibus,
    required this.totalAlunos,
    super.key,
  });

  @override
  State<EmbarqueScreen> createState() => _EmbarqueScreenState();
}

class _EmbarqueScreenState extends State<EmbarqueScreen> {
  final TextEditingController _nomeController = TextEditingController();
  final dataService = DataService();

  @override
  void initState() {
    super.initState();
    _nomeController.addListener(_filtrarPassageiros);
  }

  @override
  void dispose() {
    _nomeController.removeListener(_filtrarPassageiros);
    _nomeController.dispose();
    super.dispose();
  }

  void _filtrarPassageiros() => setState(() {});

  /// ============================================================
  /// CONFIRMAR EMBARQUE
  /// ============================================================
  Future<void> _confirmarEmbarque(Passageiro passageiro) async {
    // Embarque confirmado
    final passageiroAtualizado = passageiro.copyWith(
      embarque: 'SIM',
    );

    // Atualiza localmente e sincroniza
    dataService.updateLocalData(passageiroAtualizado, novoEmbarque: 'SIM');

    // Força rebuild da tela com novo número
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✔️ ${passageiro.nome} embarcado com sucesso!'),
        backgroundColor: Colors.green,
      ),
    );

    _nomeController.clear();
  }

  /// ============================================================
  /// CONSTRUÇÃO DA TELA
  /// ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Embarque - ${widget.colegio}'),
        backgroundColor: const Color(0xFF4C643C),
      ),
      resizeToAvoidBottomInset: true,
      body: ValueListenableBuilder<List<Passageiro>>(
        valueListenable: dataService.passageirosEmbarque,
        builder: (context, passageirosDaLista, child) {
          final termoDeBusca = _nomeController.text.trim().toLowerCase();
          final listaPassageirosFiltrada = termoDeBusca.isEmpty
              ? passageirosDaLista
              : passageirosDaLista
              .where((p) => p.nome.toLowerCase().contains(termoDeBusca))
              .toList();

          final totalEmbarcados =
              passageirosDaLista.where((p) => p.embarque == 'SIM').length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: listaPassageirosFiltrada.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildHeader(totalEmbarcados);
                    }

                    final passageiro = listaPassageirosFiltrada[index - 1];
                    final jaEmbarcou = passageiro.embarque == 'SIM';

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Card(
                        elevation: 4,
                        color: jaEmbarcou ? Colors.green.shade50 : null,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Nome: ${passageiro.nome}',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              Text('CPF: ${passageiro.cpf}'),
                              Text('Turma: ${passageiro.turma}'),
                              Text('Ônibus: ${passageiro.onibus}'),

                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Text('Status: ',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: jaEmbarcou
                                          ? Colors.green
                                          : Colors.red,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      jaEmbarcou ? 'EMBARCADO' : 'PENDENTE',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: jaEmbarcou
                                    ? null
                                    : () => _confirmarEmbarque(passageiro),
                                icon: Icon(jaEmbarcou
                                    ? Icons.check_circle
                                    : Icons.check),
                                label: Text(jaEmbarcou
                                    ? 'JÁ EMBARCADO'
                                    : 'CONFIRMAR EMBARQUE'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  jaEmbarcou ? Colors.grey : Colors.green,
                                  minimumSize: const Size.fromHeight(40),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _buildFooter(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(int totalEmbarcados) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Colégio: ${widget.colegio}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Ônibus: ${widget.onibus}',
                      style: const TextStyle(fontSize: 16)),
                  Text('Total de alunos: ${widget.totalAlunos}',
                      style: const TextStyle(fontSize: 16)),
                  Text('Total de embarques: $totalEmbarcados',
                      style: TextStyle(
                          fontSize: 16,
                          color: totalEmbarcados == widget.totalAlunos
                              ? Colors.green
                              : Colors.orange,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nomeController,
            decoration: const InputDecoration(
              labelText: 'Buscar Aluno por Nome',
              border: OutlineInputBorder(),
              suffixIcon: const Icon(Icons.search),
              prefixIcon: const Icon(Icons.person_search),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, -2)),
        ],
      ),
      child: ElevatedButton(
        onPressed: () => _showConfirmacaoEncerramento(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: const Text('ENCERRAR EMBARQUE',
            style: TextStyle(
                fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showConfirmacaoEncerramento(BuildContext context) {
    final totalEmbarcados =
        dataService.passageirosEmbarque.value.where((p) => p.embarque == 'SIM').length;
    final totalPendentes = widget.totalAlunos - totalEmbarcados;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Finalizar Embarque'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Resumo do embarque:'),
              const SizedBox(height: 8),
              Text('• Embarcados: $totalEmbarcados'),
              Text('• Pendentes: $totalPendentes'),
              const SizedBox(height: 16),
              Text(
                totalPendentes > 0
                    ? 'Ainda há $totalPendentes alunos pendentes.'
                    : 'Todos os alunos foram embarcados.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: totalPendentes > 0 ? Colors.orange : Colors.green,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Voltar para o menu de controle?',
                  style: TextStyle(fontSize: 14)),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Sim, Voltar'),
              onPressed: () => _voltarParaControle(dialogContext),
            ),
          ],
        );
      },
    );
  }

  Future<void> _voltarParaControle(BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop();
    Navigator.of(context).pop();
  }
}
