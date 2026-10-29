import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:embarqueellus/models/passageiro.dart';
import 'package:embarqueellus/services/data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RetornoService {
  static final RetornoService _instance = RetornoService._internal();

  factory RetornoService() => _instance;

  RetornoService._internal();

  final ValueNotifier<List<Passageiro>> passageirosRetorno = ValueNotifier([]);

  /// Carrega apenas os alunos que JÃ EMBARCARAM (embarque = 'SIM')
  Future<void> loadLocalDataFromEmbarque(String nomeAba, String numeroOnibus) async {
    final prefs = await SharedPreferences.getInstance();
    String? listaJson = prefs.getString('passageiros_json');

    if (listaJson != null) {
      try {
        final List<dynamic> jsonData = json.decode(listaJson);
        final List<Passageiro> todosPassageiros = List<Passageiro>.from(
            jsonData.map((json) => Passageiro.fromJson(json)));

        // âœ… FILTRAR: Apenas quem JÃ EMBARCOU
        final List<Passageiro> apenasEmbarcados = todosPassageiros
            .where((p) => p.embarque == 'SIM')
            .toList();

        passageirosRetorno.value = apenasEmbarcados;

        print('âœ… [RetornoService] ${apenasEmbarcados.length} alunos embarcados carregados');
      } catch (e) {
        print('âŒ [RetornoService] Erro ao carregar: $e');
        passageirosRetorno.value = [];
      }
    } else {
      passageirosRetorno.value = [];
      print('âš ï¸ [RetornoService] Nenhum dado local');
    }
  }

  void updateLocalData(Passageiro passageiro, {String? novoRetorno}) {
    if (novoRetorno == null) return;

    // Atualizar na lista de retorno buscando pelo CPF (ou nome caso CPF esteja vazio)
    final currentList = List<Passageiro>.from(passageirosRetorno.value);
    final cpfAlvo = (passageiro.cpf ?? '').trim();
    final index = currentList.indexWhere((p) =>
        cpfAlvo.isNotEmpty ? (p.cpf ?? '').trim() == cpfAlvo : p.nome == passageiro.nome);

    if (index != -1) {
      Passageiro updatedPassageiro = currentList[index].copyWith(
        retorno: novoRetorno,
      );

      currentList[index] = updatedPassageiro;
      passageirosRetorno.value = currentList;

      // ✅ IMPORTANTE: Atualizar também no DataService principal
      DataService().updateRetorno(passageiro, novoRetorno);

      print('📌 [RetornoService] Retorno atualizado: ${updatedPassageiro.nome} -> $novoRetorno');
    }
  }
}