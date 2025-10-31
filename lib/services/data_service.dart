import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:embarqueellus/models/passageiro.dart';
import 'package:embarqueellus/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:embarqueellus/database/database_helper.dart';

class DataService {
  static final DataService _instance = DataService._internal();

  factory DataService() => _instance;

  DataService._internal() {
    _loadPendingData();
  }

  final ValueNotifier<List<Passageiro>> passageirosEmbarque = ValueNotifier([]);

  String _nomeAba = '';
  String _numeroOnibus = '';
  Timer? _syncTimer;
  List<Map<String, dynamic>> _pendentesDeSincronizacao = [];

  // =========================================================
  // BUSCAR DADOS DO SERVIDOR
  // =========================================================
  Future<void> fetchData(String nomeAba, {String? onibus}) async {
    _nomeAba = nomeAba;
    _numeroOnibus = onibus ?? '';

    final prefs = await SharedPreferences.getInstance();
    final nomePasseio = prefs.getString('nome_passeio') ?? '';

    try {
      final url =
          '$apiUrl?colegio=$nomeAba&id_passeio=$nomePasseio&onibus=$_numeroOnibus';
      print('🔍 [DataService] URL: $url');

      final response = await http.get(Uri.parse(url));
      print('📡 [DataService] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final dynamic responseData = json.decode(response.body);

        if (responseData is Map<String, dynamic> &&
            responseData.containsKey('passageiros')) {
          final List<dynamic> passageirosJson = responseData['passageiros'];
          final List<Passageiro> fetchedList = List<Passageiro>.from(
            passageirosJson.map((json) => Passageiro.fromJson(json)),
          );

          passageirosEmbarque.value = fetchedList;
          _pendentesDeSincronizacao.clear();
          _startSyncTimer();

          await saveLocalData(nomeAba, _numeroOnibus, fetchedList);
          print('✅ [DataService] ${fetchedList.length} passageiros carregados');
        } else {
          passageirosEmbarque.value = [];
          print('⚠️ [DataService] Nenhum passageiro encontrado');
        }
      } else {
        passageirosEmbarque.value = [];
        print('❌ [DataService] Erro HTTP: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [DataService] Erro ao buscar: $e');
      await loadLocalData(_nomeAba, _numeroOnibus);
      rethrow;
    }
  }

  // =========================================================
  // SALVAR / CARREGAR LOCALMENTE
  // =========================================================
  Future<void> saveLocalData(
      String nomeAba, String onibus, List<Passageiro> lista) async {
    // Salvar em SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final listaJson = json.encode(lista.map((p) => p.toJson()).toList());
    await prefs.setString('passageiros_json', listaJson);

    final pulseira = (prefs.getString('pulseira') ?? '').toUpperCase();
    final facialLiberada = pulseira == 'SIM';

    // Salvar também no banco SQLite (tabela passageiros)
    final db = DatabaseHelper.instance;
    try {
      for (final passageiro in lista) {
        await db.insertPassageiro(passageiro);
      }
      print('💾 [DataService] ${lista.length} passageiros salvos (SharedPreferences + SQLite)');

      // Também sincronizar para tabela alunos com tem_qr='SIM'
      for (final passageiro in lista) {
        final cpf = passageiro.cpf;
        if (cpf != null && cpf.isNotEmpty) {
          final alunoExistente = await db.getAlunoByCpf(cpf);
          final statusFacial = alunoExistente?['facial'] ??
              (facialLiberada ? 'NAO' : 'BLOQUEADA');

          await db.upsertAluno({
            'cpf': cpf,
            'nome': passageiro.nome,
            'email': alunoExistente?['email'] ?? '',
            'telefone': alunoExistente?['telefone'] ?? '',
            'turma': passageiro.turma ?? alunoExistente?['turma'] ?? '',
            'facial': statusFacial,
            'tem_qr': facialLiberada ? 'SIM' : 'NAO',
          });
        }
      }
      print('✅ [DataService] Passageiros sincronizados para tabela alunos');
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
  // ATUALIZAÇÃO LOCAL + FILA DE SYNC
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
        codigoPulseira: passageiro.codigoPulseira, // mantém sempre o valor atual
      );

      currentList[index] = atualizado;
      passageirosEmbarque.value = currentList;

      String? operacao;
      String? valor;

      if (novoEmbarque != null) {
        operacao = 'embarque';
        valor = novoEmbarque;
      } else if (novoRetorno != null) {
        operacao = 'retorno';
        valor = novoRetorno;
      } else {
        print('⚠️ [DataService] Nenhuma atualização detectada para ${passageiro.nome}');
        return;
      }

      _pendentesDeSincronizacao.removeWhere(
              (item) => item['cpf'] == atualizado.cpf && item['operacao'] == operacao);

      _pendentesDeSincronizacao.add({
        'cpf': atualizado.cpf,
        'operacao': operacao,
        'valor': valor,
      });

      _savePendingData();
      saveLocalData(_nomeAba, _numeroOnibus, currentList);
      print('💾 [DataService] Atualizado localmente: ${atualizado.nome} ($operacao = $valor)');

      if (_syncTimer == null || !_syncTimer!.isActive) _startSyncTimer();
    }
  }

  // =========================================================
  // SINCRONIZAÇÃO AUTOMÁTICA COM SERVIDOR
  // =========================================================
  Future<void> _syncChanges() async {
    if (_pendentesDeSincronizacao.isEmpty) {
      _stopSyncTimer();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_sync');
      print('✅ [DataService] Sincronização concluída');
      return;
    }

    final item = _pendentesDeSincronizacao.removeAt(0);
    _savePendingData();

    try {
      final cpf = item['cpf'];
      final operacao = item['operacao'];
      final valor = item['valor'];

      if (cpf == null || cpf.toString().isEmpty) {
        print('⚠️ [DataService] CPF ausente — ignorando item.');
        return;
      }

      final passageiro = passageirosEmbarque.value.firstWhere(
            (p) => p.cpf == cpf,
        orElse: () => Passageiro(
          nome: '',
          cpf: cpf,
          idPasseio: '',
          turma: '',
          embarque: '',
          retorno: '',
          onibus: '',
          codigoPulseira: '',
        ),
      );

      final requestBody = {
        'colegio': _nomeAba,
        'cpf': cpf,
        'operacao': operacao,
      };

      // 🔥 Sempre envia a pulseira quando QR for "SIM"
      if (operacao == 'embarque') {
        requestBody['novoStatus'] = valor;
        if (valor == 'SIM') {
          requestBody['codigoPulseira'] = passageiro.codigoPulseira ?? '';
        }
      } else if (operacao == 'retorno') {
        requestBody['novoRetorno'] = valor;
      }

      print('📤 [DataService] Enviando: ${json.encode(requestBody)}');

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      );

      print('📥 [DataService] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'sucesso') {
          print('✅ [DataService] Sync OK para CPF $cpf');
        } else {
          print('⚠️ [DataService] Erro API: ${data['mensagem']}');
          if (data['status'] == 'erro') {
            _pendentesDeSincronizacao.add(item);
            _savePendingData();
          }
        }
      } else if (response.statusCode == 302) {
        print('⚠️ [DataService] Resposta 302 — verifique se o apiUrl termina com /exec');
      } else {
        print('❌ [DataService] HTTP ${response.statusCode}');
        _pendentesDeSincronizacao.add(item);
        _savePendingData();
      }
    } catch (e) {
      print('❌ [DataService] Erro ao sincronizar: $e');
      _pendentesDeSincronizacao.add(item);
      _savePendingData();
    }
  }

  // =========================================================
  // TIMER E FILA
  // =========================================================
  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) => _syncChanges());
    print('⏱️ [DataService] Timer iniciado');
  }

  void _stopSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
    print('🛑 [DataService] Timer parado');
  }

  Future<void> _savePendingData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_sync', json.encode(_pendentesDeSincronizacao));
  }

  Future<void> _loadPendingData() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getString('pending_sync');
    if (jsonList != null) {
      try {
        final List<dynamic> data = json.decode(jsonList);
        _pendentesDeSincronizacao = List<Map<String, dynamic>>.from(data);
        if (_pendentesDeSincronizacao.isNotEmpty) _startSyncTimer();
      } catch (_) {
        _pendentesDeSincronizacao.clear();
      }
    }
  }

  void updateRetorno(Passageiro passageiro, String novoRetorno) {
    updateLocalData(passageiro, novoRetorno: novoRetorno);
  }

  int getPendingCount() => _pendentesDeSincronizacao.length;

  Future<void> limparTodosDados() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    passageirosEmbarque.value = [];
    _pendentesDeSincronizacao.clear();
    _stopSyncTimer();
    print('🧹 [DataService] Todos os dados foram limpos');
  }
}

// =========================================================
// 🔍 BUSCAR UM ALUNO PELO CPF
// =========================================================
Future<Passageiro?> fetchByCpf(String colegio, String cpf) async {
  try {
    final url = '$apiUrl?colegio=$colegio&cpf=$cpf';
    print('🔍 [DataService] Buscando por CPF: $url');

    final response = await http.get(Uri.parse(url));
    print('📡 [DataService] Status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'sucesso') {
        final passageiro = Passageiro.fromJson(data);
        print('✅ [DataService] Aluno encontrado: ${passageiro.nome}');
        return passageiro;
      } else {
        print('⚠️ [DataService] ${data['mensagem']}');
      }
    } else {
      print('❌ [DataService] Erro HTTP: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ [DataService] Erro ao buscar CPF: $e');
  }
  return null;
}
