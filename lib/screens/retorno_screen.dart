import 'package:flutter/material.dart';
import 'package:embarqueellus/models/passageiro.dart';
import 'package:embarqueellus/services/retorno_service.dart';


class RetornoScreen extends StatefulWidget {
  final String colegio;
  final String onibus;
  final int totalAlunos;

  const RetornoScreen({
    required this.colegio,
    required this.onibus,
    required this.totalAlunos,
    super.key
  });

  @override
  State<RetornoScreen> createState() => _RetornoScreenState();
}

class _RetornoScreenState extends State<RetornoScreen> {
  final TextEditingController _nomeController = TextEditingController();
  final retornoService = RetornoService();

  @override
  void initState() {
    super.initState();
    _nomeController.addListener(_filtrarPassageiros);
    print('📌 [RetornoScreen] Tela de retorno iniciada para ${widget.colegio}');
  }

  @override
  void dispose() {
    _nomeController.removeListener(_filtrarPassageiros);
    _nomeController.dispose();
    super.dispose();
  }

  void _filtrarPassageiros() {
    setState(() {});
  }

  void _confirmarRetorno(Passageiro passageiro) {
    print('📌 [RetornoScreen] Confirmando retorno: ${passageiro.nome}');
    retornoService.updateLocalData(passageiro, novoRetorno: 'SIM');
    _nomeController.clear();
  }

  Future<void> _desfazerRetorno(Passageiro passageiro) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desfazer Retorno'),
        content: Text('Deseja desmarcar o retorno de ${passageiro.nome}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Desmarcar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    retornoService.updateLocalData(passageiro, novoRetorno: 'NÃO');
    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('↩️ Retorno de ${passageiro.nome} desmarcado.'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Retorno - ${widget.colegio}'),
        backgroundColor: Colors.orange.shade700,
      ),
      // Adicionado resizeToAvoidBottomInset
      resizeToAvoidBottomInset: true,
      body: ValueListenableBuilder<List<Passageiro>>(
        valueListenable: retornoService.passageirosRetorno,
        builder: (context, passageirosDaLista, child) {
          final termoDeBusca = _nomeController.text.trim().toLowerCase();
          final listaPassageirosFiltrada = termoDeBusca.isEmpty
              ? passageirosDaLista
              : passageirosDaLista.where((p) => p.nome.toLowerCase().contains(termoDeBusca)).toList();

          final totalRetornados = passageirosDaLista.where((p) => p.retorno == 'SIM').length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // CORRIGIDO: Removido o Padding/Column fixo e colocado o conteúdo em ListView.builder abaixo.
              Expanded(
                child: ListView.builder(
                  // Total de itens: 1 (Padding/Card/Search) + o número de passageiros filtrados
                  itemCount: listaPassageirosFiltrada.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // O primeiro item é o cabeçalho com o Card de Resumo e a Busca
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Card(
                              elevation: 4,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Colégio: ${widget.colegio}',
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    Text('Ônibus: ${widget.onibus}',
                                        style: const TextStyle(fontSize: 16)),
                                    Text('Total de alunos embarcados: ${widget.totalAlunos}',
                                        style: const TextStyle(fontSize: 16)),
                                    Text('Total de retornos: $totalRetornados',
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: totalRetornados == widget.totalAlunos ? Colors.green : Colors.orange,
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
                                suffixIcon: Icon(Icons.search),
                                prefixIcon: Icon(Icons.person_search),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Se a busca não encontrou ninguém, mostramos a mensagem aqui
                            if (listaPassageirosFiltrada.isEmpty && termoDeBusca.isNotEmpty)
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.search_off, size: 48, color: Colors.grey),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Nenhum aluno encontrado com "$termoDeBusca"',
                                      style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                ),
                              ),
                            // Se a lista está vazia (por não ter alunos embarcados)
                            if (passageirosDaLista.isEmpty && termoDeBusca.isEmpty)
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.search_off, size: 48, color: Colors.grey),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Nenhum aluno embarcado encontrado.',
                                      style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    }

                    // Os itens restantes são os passageiros (index - 1)
                    final passageiro = listaPassageirosFiltrada[index - 1];
                    final jaRetornou = passageiro.retorno == 'SIM';

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      child: Card(
                        elevation: 4,
                        color: jaRetornou ? Colors.green.shade50 : null,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Nome: ${passageiro.nome}',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('ID Passeio: ${passageiro.idPasseio}'),
                              if (passageiro.colegio != null && passageiro.colegio!.isNotEmpty)
                                Text('Colégio: ${passageiro.colegio}'),
                              Text('Turma: ${passageiro.turma}'),
                              Text('Ônibus: ${passageiro.onibus}'),
                              Row(
                                children: [
                                  const Text('Status Embarque: ',
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'EMBARCADO',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('Status Retorno: ',
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: jaRetornou ? Colors.green : Colors.orange,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      jaRetornou ? 'RETORNOU' : 'PENDENTE',
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
                                onPressed: jaRetornou
                                    ? () => _desfazerRetorno(passageiro)
                                    : () => _confirmarRetorno(passageiro),
                                icon: Icon(jaRetornou ? Icons.undo : Icons.check),
                                label: Text(jaRetornou
                                    ? 'RETORNOU (TOQUE P/ DESFAZER)'
                                    : 'CONFIRMAR RETORNO'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: jaRetornou ? Colors.blueGrey : Colors.orange.shade700,
                                  foregroundColor: Colors.white,
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
              // Rodapé fixo
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () => _showConfirmacaoEncerramento(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                  ),
                  child: const Text('ENCERRAR RETORNO',
                      style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showConfirmacaoEncerramento(BuildContext context) {
// ... (restante do código da RetornoScreen permanece o mesmo)
    final totalRetornados = retornoService.passageirosRetorno.value.where((p) => p.retorno == 'SIM').length;
    final totalPendentes = widget.totalAlunos - totalRetornados;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Finalizar Retorno'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Resumo do retorno:'),
              const SizedBox(height: 8),
              Text('• Retornados: $totalRetornados'),
              Text('• Pendentes: $totalPendentes'),
              const SizedBox(height: 16),
              Text(
                totalPendentes > 0
                    ? 'Ainda há $totalPendentes alunos pendentes.'
                    : 'Todos os alunos retornaram.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: totalPendentes > 0 ? Colors.orange : Colors.green,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Voltar para o menu de controle?',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Sim, Voltar'),
              onPressed: () {
                _voltarParaControle(dialogContext);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _voltarParaControle(BuildContext dialogContext) async {
    print('📌 [RetornoScreen] Voltando para Controle de Embarque...');

    Navigator.of(dialogContext).pop(); // Fecha dialog
    Navigator.of(context).pop(); // Volta para Controle Embarque
  }
}