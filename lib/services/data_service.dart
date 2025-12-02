import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:embarqueellus/models/passageiro.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/firebase_service.dart';

class DataService {
  static final DataService _instance = DataService._internal();

  factory DataService() => _instance;

  DataService._internal() {
    _loadPendingData();
    _initRealtimeListener();
  }

  final FirebaseService _firebaseService = FirebaseService.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final ValueNotifier<List<Passageiro>> passageirosEmbarque = ValueNotifier([]);

  String _nomeAba = '';
  String _numeroOnibus = '';
  Timer? _syncTimer;
  List<Map<String, dynamic>> _pendentesDeSincronizacao = [];

  // =========================================================
  // LISTENER EM TEMPO REAL
  // =========================================================
  StreamSubscription? _embarqueListener;

  void _initRealtimeListener() {
    // O listener será inicializado quando fetchData for chamado
  }

  void _startListeningToEmbarques(String colegio, String idPasseio, String onibus) {
    _embarqueListener?.cancel();

    Query query = _firestore.collection('embarques')
        .where('colegio', isEqualTo: colegio)
        .where('idPasseio', isEqualTo: idPasseio);

    if (onibus.isNotEmpty) {
      query = query.where('onibus', isEqualTo: onibus);
    }

    _embarqueListener = query.snapshots().listen((snapshot) {
      final passageiros = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Passageiro.fromJson(data);
      }).toList();

      passageirosEmbarque.value = passageiros;
      saveLocalData(colegio, onibus, passageiros);
      print('✅ [DataService] ${passageiros.length} passageiros atualizados via Firebase');
    });
  }

  // =========================================================
  // BUSCAR DADOS DO FIREBASE
  // =========================================================
  Future<void> fetchData(String nomeAba, {String? onibus}) async {
    _nomeAba = nomeAba;
    _numeroOnibus = onibus ?? '';

    final prefs = await SharedPreferences.getInstance();
    final nomePasseio = prefs.getString('nome_passeio') ?? '';

    try {
      print('🔍 [DataService] Buscando do Firebase: colegio=$nomeAba, passeio=$nomePasseio, onibus=$_numeroOnibus');

      // Iniciar listener em tempo real
      _startListeningToEmbarques(_nomeAba, nomePasseio, _numeroOnibus);

      // Buscar dados iniciais
      Query query = _firestore.collection('embarques')
          .where('colegio', isEqualTo: _nomeAba)
          .where('idPasseio', isEqualTo: nomePasseio);

      if (_numeroOnibus.isNotEmpty) {
        query = query.where('onibus', isEqualTo: _numeroOnibus);
      }

      final snapshot = await query.get();
      final List<Passageiro> fetchedList = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Passageiro.fromJson(data);
      }).toList();

      passageirosEmbarque.value = fetchedList;
      _pendentesDeSincronizacao.clear();
      _startSyncTimer();

      await saveLocalData(nomeAba, _numeroOnibus, fetchedList);
      print('✅ [DataService] ${fetchedList.length} passageiros carregados do Firebase');
    } catch (e) {
      print('❌ [DataService] Erro ao buscar do Firebase: $e');
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

    // ❌ REMOVIDO: Lógica de pulseira não é mais necessária

    // Salvar também no banco SQLite (tabela passageiros)
    final db = DatabaseHelper.instance;
    try {
      for (final passageiro in lista) {
        await db.insertPassageiro(passageiro);
      }
      print('💾 [DataService] ${lista.length} passageiros salvos (SharedPreferences + SQLite)');

      // 🔧 REFATORAÇÃO v10: Tabela unificada 'alunos'
      // A tabela 'alunos' contém tanto dados de alunos quanto informações de embarque/retorno
      // As antigas tabelas separadas (pessoas_facial, passageiros) foram unificadas
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
  // SINCRONIZAÇÃO AUTOMÁTICA COM FIREBASE
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
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final nomePasseio = prefs.getString('nome_passeio') ?? '';
      final colegio = prefs.getString('nome_aba') ?? '';

      // ✅ CORREÇÃO: Enviar TODOS os dados do passageiro para criar documento completo
      final updateData = <String, dynamic>{
        'cpf': cpf,
        'nome': passageiro.nome,
        'colegio': colegio,
        'turma': passageiro.turma ?? '',
        'idPasseio': nomePasseio,
        'onibus': _numeroOnibus,
      };

      // Atualizar campo específico
      if (operacao == 'embarque') {
        updateData['embarque'] = valor;
      } else if (operacao == 'retorno') {
        updateData['retorno'] = valor;
      }
      updateData['updated_at'] = FieldValue.serverTimestamp();

      // ✅ Usar apenas CPF como docId
      final docId = cpf;

      print('📤 [DataService] Enviando para Firebase: $docId - $updateData');

      await _firestore.collection('embarques').doc(docId).set(updateData, SetOptions(merge: true));

      print('✅ [DataService] Sync OK para CPF $cpf');
    } catch (e) {
      print('❌ [DataService] Erro ao sincronizar com Firebase: $e');
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
    print('🔍 [DataService] Buscando por CPF no Firebase: $cpf');

    final snapshot = await FirebaseFirestore.instance
        .collection('embarques')
        .where('colegio', isEqualTo: colegio)
        .where('cpf', isEqualTo: cpf)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      final data = snapshot.docs.first.data();
      final passageiro = Passageiro.fromJson(data);
      print('✅ [DataService] Aluno encontrado: ${passageiro.nome}');
      return passageiro;
    } else {
      print('⚠️ [DataService] Aluno não encontrado com CPF: $cpf');
    }
  } catch (e) {
    print('❌ [DataService] Erro ao buscar CPF no Firebase: $e');
  }
  return null;
}
