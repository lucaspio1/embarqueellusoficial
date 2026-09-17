import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:embarqueellus/models/passageiro.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/firebase_service.dart';

class DataService {
  static final DataService _instance = DataService._internal();

  factory DataService() => _instance;

  DataService._internal() {
    // Sincronização centralizada agora ocorre via FirebaseService
  }

  final FirebaseService _firebaseService = FirebaseService.instance;

  final ValueNotifier<List<Passageiro>> passageirosEmbarque = ValueNotifier([]);

  String _nomeAba = '';
  String _numeroOnibus = '';

  // =========================================================
  // BUSCAR DADOS (VIA FIREBASE SERVICE / API REST)
  // =========================================================
  Future<void> fetchData(String nomeAba, {String? onibus}) async {
    _nomeAba = nomeAba;
    _numeroOnibus = onibus ?? '';

    final prefs = await SharedPreferences.getInstance();
    final nomePasseio = prefs.getString('nome_passeio') ?? '';

    try {
      print('🔍 [DataService] Buscando dados via API: colegio=$nomeAba, passeio=$nomePasseio, onibus=$_numeroOnibus');

      // Buscar do FirebaseService (que tentará API REST ou SQLite)
      final embarquesRaw = await _firebaseService.buscarEmbarques(
        idPasseio: nomePasseio,
        onibus: _numeroOnibus.isNotEmpty ? _numeroOnibus : null,
      );

      // Converter e aplicar filtro de colégio (nomeAba)
      List<Passageiro> fetchedList = embarquesRaw
          .where((data) => (data['colegio'] ?? data['escola'] ?? '') == nomeAba)
          .map((data) => Passageiro.fromJson(data))
          .toList();

      passageirosEmbarque.value = fetchedList;

      await saveLocalData(nomeAba, _numeroOnibus, fetchedList);
      print('✅ [DataService] ${fetchedList.length} passageiros carregados');
    } catch (e) {
      print('❌ [DataService] Erro ao buscar dados: $e');
      await loadLocalData(_nomeAba, _numeroOnibus);
      rethrow;
    }
  }

  // =========================================================
  // SALVAR / CARREGAR LOCALMENTE
  // =========================================================
  Future<void> saveLocalData(String nomeAba, String onibus, List<Passageiro> lista) async {
    final prefs = await SharedPreferences.getInstance();
    final listaJson = json.encode(lista.map((p) => p.toJson()).toList());
    await prefs.setString('passageiros_json', listaJson);

    final db = DatabaseHelper.instance;
    try {
      for (final passageiro in lista) {
        await db.insertPassageiro(passageiro);
      }
      print('💾 [DataService] ${lista.length} passageiros salvos localmente');
    } catch (e) {
      print('❌ [DataService] Erro ao salvar no SQLite: $e');
    }
  }

  Future<void> loadLocalData(String nomeAba, String onibus) async {
    _nomeAba = nomeAba;
    _numeroOnibus = onibus;

    final prefs = await SharedPreferences.getInstance();
    final listaJson = prefs.getString('passageiros_json');

    if (listaJson != null) {
      try {
        final List<dynamic> jsonData = json.decode(listaJson);
        final List<Passageiro> loadedList = List<Passageiro>.from(
          jsonData.map((json) => Passageiro.fromJson(json)),
        );
        passageirosEmbarque.value = loadedList;
        print('✅ [DataService] Dados carregados do local');
      } catch (e) {
        passageirosEmbarque.value = [];
        print('❌ [DataService] Erro ao carregar local: $e');
      }
    } else {
      passageirosEmbarque.value = [];
      print('⚠️ [DataService] Nenhum dado local');
    }
  }

  // =========================================================
  // ATUALIZAÇÃO E ENFILEIRAMENTO
  // =========================================================
  void updateLocalData(
      Passageiro passageiro, {
        String? novoEmbarque,
        String? novoRetorno,
      }) {
    final currentList = List<Passageiro>.from(passageirosEmbarque.value);
    final index = currentList.indexWhere((p) => p.cpf == passageiro.cpf);

    if (index != -1) {
      final atualizado = currentList[index].copyWith(
        embarque: novoEmbarque ?? passageiro.embarque,
        retorno: novoRetorno ?? passageiro.retorno,
      );

      currentList[index] = atualizado;
      passageirosEmbarque.value = currentList;

      saveLocalData(_nomeAba, _numeroOnibus, currentList);
      print('💾 [DataService] Atualizado na UI: ${atualizado.nome}');

      // Delega a atualização e sincronização em lote para o FirebaseService
      _firebaseService.atualizarEmbarque(
        cpf: atualizado.cpf ?? '',
        idPasseio: atualizado.idPasseio ?? '',
        onibus: _numeroOnibus.isNotEmpty ? _numeroOnibus : atualizado.onibus,
        embarque: novoEmbarque,
        retorno: novoRetorno,
      ).catchError((e) {
        print('⚠️ [DataService] Erro ao delegar atualização para o FirebaseService: $e');
      });
    }
  }

  void updateRetorno(Passageiro passageiro, String novoRetorno) {
    updateLocalData(passageiro, novoRetorno: novoRetorno);
  }

  // Retorna 0 pois o FirebaseService agora gerencia a fila principal
  int getPendingCount() => 0;

  Future<void> limparTodosDados() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    passageirosEmbarque.value = [];
    print('🧹 [DataService] Todos os dados foram limpos');
  }
}

// =========================================================
// 🔍 BUSCAR UM ALUNO PELO CPF (Global function)
// =========================================================
Future<Passageiro?> fetchByCpf(String colegio, String cpf) async {
  try {
    print('🔍 [DataService] Buscando por CPF no SQLite: $cpf');
    
    // Como os dados vêm do delta sync, buscar direto no SQLite
    final db = await DatabaseHelper.instance.database;
    final results = await db.query(
      'embarques',
      where: 'colegio = ? AND cpf = ?',
      whereArgs: [colegio, cpf],
      limit: 1,
    );

    if (results.isNotEmpty) {
      final passageiro = Passageiro.fromJson(results.first);
      print('✅ [DataService] Aluno encontrado: ${passageiro.nome}');
      return passageiro;
    } else {
      print('⚠️ [DataService] Aluno não encontrado com CPF: $cpf');
    }
  } catch (e) {
    print('❌ [DataService] Erro ao buscar CPF no SQLite: $e');
  }
  return null;
}
