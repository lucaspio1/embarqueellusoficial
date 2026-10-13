// lib/services/firebase_service.dart
// Serviço principal de sincronização — agora usa REST API do backend Node.js
// Em vez de 120+ apps acessando Firestore diretamente, todos passam pelo backend.
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/api_service.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';

class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final DatabaseHelper _db = DatabaseHelper.instance;
  final ApiService _api = ApiService.instance;

  Timer? _syncTimer;
  bool _isSyncing = false;

  // ValueNotifier para que widgets possam observar o estado de sincronização
  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);

  /// Embarque/retorno que chegaram do servidor no último delta, por CPF
  /// (ex.: marcados pelo painel web ou por outro monitor). As telas de
  /// embarque e retorno escutam para atualizar sem precisar ler o QR de novo.
  final ValueNotifier<Map<String, Map<String, String>>> embarquesDoServidor =
      ValueNotifier<Map<String, Map<String, String>>>({});

  void init() {
    _syncTimer?.cancel();

    // Inicializar o ApiService (carregar token salvo)
    _api.init();

    // Sincronização automática a cada 60 segundos via REST delta
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      print('⏰ [FirebaseService] Timer de sincronização disparado');
      await trySyncInBackground();
    });

    print('✅ [FirebaseService] Sincronização via REST API iniciada (intervalo: 60s)');
    trySyncInBackground();
  }

  void dispose() {
    _syncTimer?.cancel();
  }

  // =============================
  // HELPER: Campo case-insensitive
  // =============================

  /// Helper para ler campo de Map aceitando maiúsculo ou minúsculo
  dynamic _getField(Map<String, dynamic> data, String fieldName, [dynamic defaultValue]) {
    if (data.containsKey(fieldName)) {
      return data[fieldName] ?? defaultValue;
    }
    final upperFieldName = fieldName.toUpperCase();
    if (data.containsKey(upperFieldName)) {
      return data[upperFieldName] ?? defaultValue;
    }
    final capitalizedFieldName = fieldName[0].toUpperCase() + fieldName.substring(1);
    if (data.containsKey(capitalizedFieldName)) {
      return data[capitalizedFieldName] ?? defaultValue;
    }
    return defaultValue;
  }

  /// Converte datas em vários formatos para string dd/MM/yyyy
  String _convertTimestampToDate(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return '';
  }

  // =============================
  // SINCRONIZAÇÃO DELTA VIA REST
  // =============================

  /// Sincronização delta: baixa apenas o que mudou desde a última sync
  Future<void> _syncDelta() async {
    try {
      if (!_api.isAuthenticated) {
        print('⚠️ [FirebaseService] API não autenticada, pulando sync delta');
        return;
      }

      // Obter timestamp da última sincronização
      final db = await _db.database;
      final metaRows = await db.query(
        'sync_metadata',
        where: 'chave = ?',
        whereArgs: ['last_delta_sync'],
        limit: 1,
      );
      
      String? lastSync;
      if (metaRows.isNotEmpty) {
        lastSync = metaRows.first['valor'] as String?;
      }

      final response = await _api.syncDelta(lastSync);
      final faltaAlguem = await _processarRespostaDelta(db, response);

      // Uma viagem entrou na janela (ex.: começa daqui a 3 dias) mas os
      // alunos dela não mudaram desde a última sync: busca tudo de novo.
      // Limitado a 1 vez a cada 10 min para não repetir sem parar.
      if (faltaAlguem && lastSync != null && await _podeFazerSyncCompleto(db)) {
        print('🔄 [FirebaseService] Viagem nova no escopo: sync completo');
        final completo = await _api.syncDelta(null);
        await _processarRespostaDelta(db, completo);
      }
    } catch (e) {
      print('⚠️ [FirebaseService] Erro no sync delta: $e');
    }
  }

  /// Aplica uma resposta do delta. Retorna true se o escopo tem alunos que
  /// ainda não estão no aparelho.
  Future<bool> _processarRespostaDelta(Database db, Map<String, dynamic> response) async {
    if (response['success'] != true) return false;
    final delta = response['delta'] as Map<String, dynamic>? ?? {};
    final serverTime = response['serverTime'] as String?;

    await _applyDelta(delta);

    var faltaAlguem = false;
    final escopo = response['escopo'];
    if (escopo is Map && escopo['cpfs'] is List) {
      faltaAlguem = await _aplicarEscopo(db, (escopo['cpfs'] as List).map((c) => c.toString()).toSet());
    }

    if (serverTime != null) {
      await db.insert(
        'sync_metadata',
        {'chave': 'last_delta_sync', 'valor': serverTime, 'updated_at': serverTime},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final totalDocs = delta.values.fold<int>(0, (sum, list) => sum + (list as List).length);
    if (totalDocs > 0) {
      print('✅ [FirebaseService] Delta sync: $totalDocs docs recebidos');
    }
    return faltaAlguem;
  }

  /// Remove do aparelho alunos, quartos e embarques de viagens que saíram do
  /// escopo (encerradas ou de outras datas). Dados pessoais e faciais que o
  /// monitor não precisa não ficam no celular. Retorna true se falta trazer
  /// algum CPF do escopo.
  Future<bool> _aplicarEscopo(Database db, Set<String> ativos) async {
    var removidos = 0;
    final presentes = <String>{};
    for (final tabela in const ['alunos', 'quartos', 'embarques']) {
      final rows = await db.query(tabela, columns: ['cpf']);
      final locais = rows.map((r) => (r['cpf'] ?? '').toString()).toSet();
      presentes.addAll(locais.where(ativos.contains));
      final fora = locais.difference(ativos).toList();
      for (var i = 0; i < fora.length; i += 500) {
        final fim = i + 500 < fora.length ? i + 500 : fora.length;
        final parte = fora.sublist(i, fim);
        removidos += await db.delete(
          tabela,
          where: 'cpf IN (${List.filled(parte.length, '?').join(',')})',
          whereArgs: parte,
        );
      }
    }
    if (removidos > 0) {
      print('🧹 [FirebaseService] $removidos registro(s) de viagens fora do escopo removidos do aparelho');
      FaceRecognitionService.instance.invalidateCache();
    }
    return ativos.difference(presentes).isNotEmpty;
  }

  Future<bool> _podeFazerSyncCompleto(Database db) async {
    final rows = await db.query('sync_metadata', where: 'chave = ?', whereArgs: ['ultimo_sync_completo'], limit: 1);
    final ultimo = rows.isNotEmpty ? DateTime.tryParse((rows.first['valor'] ?? '').toString()) : null;
    if (ultimo != null && DateTime.now().difference(ultimo).inMinutes < 10) return false;
    final agora = DateTime.now().toIso8601String();
    await db.insert(
      'sync_metadata',
      {'chave': 'ultimo_sync_completo', 'valor': agora, 'updated_at': agora},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return true;
  }

  /// Aplica os dados delta recebidos no SQLite local
  Future<void> _applyDelta(Map<String, dynamic> delta) async {
    final db = await _db.database;

    // Aplicar alunos
    if (delta.containsKey('alunos')) {
      final alunos = delta['alunos'] as List;
      final movPendentes = await _movimentacoesPendentes(db);
      final batch = db.batch();
      for (var aluno in alunos) {
        final data = aluno as Map<String, dynamic>;
        final cpf = _getField(data, 'cpf', '');
        if (cpf.isEmpty) continue;

        final embeddingData = _getField(data, 'embedding');
        String embeddingJson = '';
        if (embeddingData != null) {
          if (embeddingData is List) {
            embeddingJson = '[${embeddingData.map((e) => (e as num).toDouble()).join(',')}]';
          } else if (embeddingData is String && embeddingData.isNotEmpty) {
            embeddingJson = embeddingData;
          }
        }

        final facialCadastrada = _getField(data, 'facial_cadastrada', false) == true ? 1 : 0;

        batch.insert(
          'alunos',
          {
            'cpf': cpf,
            'nome': _getField(data, 'nome', ''),
            'colegio': _getField(data, 'colegio', ''),
            'email': _getField(data, 'email', ''),
            'telefone': _getField(data, 'telefone', ''),
            'turma': _getField(data, 'turma', ''),
            'tem_qr': _getField(data, 'tem_qr', false) == true ? 'SIM' : 'NAO',
            'inicio_viagem': _convertTimestampToDate(_getField(data, 'inicio_viagem')),
            'fim_viagem': _convertTimestampToDate(_getField(data, 'fim_viagem')),
            'embedding': embeddingJson,
            'facial_cadastrada': facialCadastrada,
            'data_cadastro_facial': _convertTimestampToDate(_getField(data, 'data_cadastro_facial')),
            'embarcado': _getField(data, 'embarcado', false) == true ? 1 : 0,
            'data_embarque': _convertTimestampToDate(_getField(data, 'data_embarque')),
            'retornado': _getField(data, 'retornado', false) == true ? 1 : 0,
            'data_retorno': _convertTimestampToDate(_getField(data, 'data_retorno')),
            'movimentacao': movPendentes[cpf] ?? _getField(data, 'movimentacao', 'QUARTO'),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }

    // Aplicar quartos
    if (delta.containsKey('quartos')) {
      final quartos = delta['quartos'] as List;
      final batch = db.batch();
      for (var quarto in quartos) {
        final data = quarto as Map<String, dynamic>;
        final cpfQuarto = (_getField(data, 'cpf', '') ?? '').toString().trim();
        if (cpfQuarto.isEmpty) continue;
        // CPF é único em `quartos` desde a v12 do banco: REPLACE substitui
        // a linha do aluno em vez de inserir outra (antes duplicava faciais)
        batch.insert(
          'quartos',
          {
            'numero_quarto': _getField(data, 'numero_quarto', ''),
            'escola': _getField(data, 'colegio', '') ?? _getField(data, 'escola', ''),
            'nome_hospede': _getField(data, 'nome_hospede', ''),
            'cpf': cpfQuarto,
            'inicio_viagem': _convertTimestampToDate(_getField(data, 'inicio_viagem')),
            'fim_viagem': _convertTimestampToDate(_getField(data, 'fim_viagem')),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }

    // Aplicar embarques
    if (delta.containsKey('embarques')) {
      final embarques = delta['embarques'] as List;
      // Marcações feitas offline e ainda não confirmadas prevalecem sobre o servidor
      final pendentes = await getEmbarquesPendentes();
      final recebidos = <String, Map<String, String>>{};
      final batch = db.batch();
      for (var embarque in embarques) {
        final data = embarque as Map<String, dynamic>;
        final cpf = _getField(data, 'cpf', '');
        if (cpf.isEmpty) continue;
        final pendente = pendentes[cpf] ?? const <String, String>{};
        recebidos[cpf.toString()] = {
          'embarque': (pendente['embarque'] ?? _getField(data, 'embarque', '') ?? '').toString(),
          'retorno': (pendente['retorno'] ?? _getField(data, 'retorno', '') ?? '').toString(),
        };

        batch.insert(
          'embarques',
          {
            'cpf': cpf,
            'nome': _getField(data, 'nome', ''),
            'colegio': _getField(data, 'colegio', ''),
            'turma': _getField(data, 'turma', ''),
            'id_passeio': _getField(data, 'idPasseio', ''),
            'onibus': _getField(data, 'onibus', ''),
            'inicio_viagem': _convertTimestampToDate(_getField(data, 'inicioViagem')),
            'fim_viagem': _convertTimestampToDate(_getField(data, 'fimViagem')),
            'embarque': pendente['embarque'] ?? _getField(data, 'embarque', ''),
            'retorno': pendente['retorno'] ?? _getField(data, 'retorno', ''),
            'facial_cadastrada': _getField(data, 'facial_cadastrada', false) == true ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      if (recebidos.isNotEmpty) embarquesDoServidor.value = recebidos;
    }

    // Aplicar eventos
    if (delta.containsKey('eventos')) {
      final eventos = delta['eventos'] as List;
      for (var evento in eventos) {
        final data = evento as Map<String, dynamic>;
        final tipoEvento = data['tipo_evento'] as String?;
        if (tipoEvento == 'viagem_encerrada') {
          print('🔔 [FirebaseService] Evento delta: Viagem encerrada detectada');
        }
      }
    }
  }

  // =============================
  // UPLOAD DE PENDÊNCIAS VIA REST
  // =============================

  /// Envia operações pendentes (logs, movimentações, embeddings, embarques).
  ///
  /// Ao reconectar, esvazia a fila em rodadas (o sinal pode durar pouco).
  Future<void> _uploadPending() async {
    if (!_api.isAuthenticated) {
      print('⚠️ [FirebaseService] Sem token: pendências ficam na fila local');
      return;
    }
    for (var rodada = 0; rodada < _maxRodadasUpload; rodada++) {
      final continuar = await _uploadPendingRodada();
      if (!continuar) break;
    }
  }

  static const int _maxRodadasUpload = 20;
  static const int _tamanhoLote = 50;

  /// Envia um lote. Retorna true se ainda pode haver mais itens na fila.
  Future<bool> _uploadPendingRodada() async {
    try {
      final db = await _db.database;
      final operations = <Map<String, dynamic>>[];

      // 1. Logs pendentes (+ movimentação derivada de cada log)
      final pendingLogs = await db.query(
        'logs',
        where: 'sincronizado = ?',
        whereArgs: [0],
        orderBy: 'id ASC',
        limit: _tamanhoLote,
      );

      for (final log in pendingLogs) {
        // Horário real do evento, em UTC: o servidor usa para o ID do log
        // (reenvio não duplica) e para não aplicar movimentação antiga.
        final eventAt = _paraIsoUtc(log['timestamp']);
        operations.add({
          'id': 'log_${log['id']}',
          'type': 'log',
          'data': {
            if (eventAt != null) 'event_at': eventAt,
            'cpf': log['cpf'],
            'person_name': log['person_name'],
            'timestamp': log['timestamp'],
            'confidence': log['confidence'],
            'tipo': log['tipo'],
            'operador_nome': log['operador_nome'] ?? '',
            'colegio': log['colegio'] ?? '',
            'turma': log['turma'] ?? '',
            'inicio_viagem': log['inicio_viagem'] ?? '',
            'fim_viagem': log['fim_viagem'] ?? '',
          }
        });

        final tipo = (log['tipo'] ?? '').toString().trim().toUpperCase();
        if (tipo.isNotEmpty && tipo != 'RECONHECIMENTO' && tipo != 'FACIAL') {
          operations.add({
            'id': 'mov_${log['id']}',
            'type': 'movimentacao',
            'data': {
              'cpf': (log['cpf'] ?? '').toString(),
              'nome': log['person_name'] ?? '',
              'movimentacao': tipo,
              'operador': log['operador_nome'] ?? '',
              if (eventAt != null) 'event_at': eventAt,
            }
          });
        }
      }

      // 2. Fila durável (cadastros faciais, embarques/retornos)
      final outbox = await _db.getOutboxBatch(limit: _tamanhoLote);
      final outboxDescartar = <int>[];
      for (final row in outbox) {
        final rowId = row['id'] as int;
        try {
          final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
          final tipo = row['tipo'] as String;

          if (tipo == 'face_register') {
            operations.add({
              'id': 'outbox_$rowId',
              'type': 'embedding',
              'data': {
                'cpf': payload['cpf'].toString().trim(),
                'embedding': payload['embedding'],
              }
            });
          } else if (tipo == _tipoEmbarque) {
            operations.add({
              'id': 'outbox_$rowId',
              'type': 'embarque',
              'data': payload,
            });
          } else {
            print('⚠️ [FirebaseService] Item de fila com tipo desconhecido "$tipo" descartado (id $rowId)');
            outboxDescartar.add(rowId);
          }
        } catch (e) {
          print('⚠️ [FirebaseService] Item de fila ilegível descartado (id $rowId): $e');
          outboxDescartar.add(rowId);
        }
      }
      if (outboxDescartar.isNotEmpty) await _db.deleteOutboxIds(outboxDescartar);

      if (operations.isEmpty) return false;

      print('📤 [FirebaseService] Enviando ${operations.length} operações pendentes...');
      final response = await _api.uploadBatch(operations);
      if (response['success'] != true) return false;

      // Status por operação. Servidor antigo (sem `results`) = tudo ok.
      final status = <String, String>{};
      final results = response['results'];
      if (results is List) {
        for (final r in results) {
          if (r is Map && r['id'] != null) {
            status[r['id'].toString()] = (r['status'] ?? 'error').toString();
          }
        }
      }
      bool confirmado(String opId) {
        if (results is! List) return true;
        final s = status[opId];
        return s == 'ok' || s == 'skipped';
      }

      final logsConfirmados = <int>[];
      for (final log in pendingLogs) {
        final id = log['id'] as int;
        final movOk = !operations.any((o) => o['id'] == 'mov_$id') || confirmado('mov_$id');
        if (confirmado('log_$id') && movOk) logsConfirmados.add(id);
      }
      await _db.marcarLogsSincronizados(logsConfirmados);

      final outboxConfirmados = outbox
          .map((row) => row['id'] as int)
          .where((id) => !outboxDescartar.contains(id) && confirmado('outbox_$id'))
          .toList();
      await _db.deleteOutboxIds(outboxConfirmados);

      final falhas = (pendingLogs.length - logsConfirmados.length) +
          (outbox.length - outboxDescartar.length - outboxConfirmados.length);
      print('✅ [FirebaseService] Confirmados: ${logsConfirmados.length} logs, '
          '${outboxConfirmados.length} itens da fila${falhas > 0 ? ' — $falhas aguardando nova tentativa' : ''}');

      // Continua se havia lote cheio e algo avançou nesta rodada
      final avancou = logsConfirmados.isNotEmpty || outboxConfirmados.isNotEmpty;
      final loteCheio = pendingLogs.length == _tamanhoLote || outbox.length == _tamanhoLote;
      return avancou && loteCheio;
    } catch (e) {
      print('❌ [FirebaseService] Erro ao enviar pendências: $e');
      Sentry.captureException(e);
      return false;
    }
  }

  // =============================
  // ENFILEIRAMENTO DE DADOS
  // =============================

  Future<void> queueLogAcesso({
    required String cpf,
    required String personName,
    required DateTime timestamp,
    required double confidence,
    required String personId,
    required String tipo,
    String? operadorNome,
    String? colegio,
    String? turma,
    String? inicioViagem,
    String? fimViagem,
  }) async {
    // Salvar localmente primeiro (offline-first)
    await _db.insertLog(
      cpf: cpf,
      personName: personName,
      timestamp: timestamp,
      confidence: confidence,
      tipo: tipo,
      operadorNome: operadorNome,
      colegio: colegio,
      turma: turma,
      inicioViagem: inicioViagem,
      fimViagem: fimViagem,
    );

    // Atualizar movimentação local
    final tipoNormalizado = tipo.trim().toUpperCase();
    if (tipoNormalizado.isNotEmpty &&
        tipoNormalizado != 'RECONHECIMENTO' &&
        tipoNormalizado != 'FACIAL') {
      try {
        final db = await _db.database;
        await db.update(
          'alunos',
          {'movimentacao': tipoNormalizado},
          where: 'cpf = ?',
          whereArgs: [cpf],
        );
      } catch (_) {}
    }

    // Tentar enviar via API REST imediatamente
    try {
      if (_api.isAuthenticated && await _hasInternet()) {
        await _api.uploadBatch([
          {
            'id': 'log_immediate_${DateTime.now().millisecondsSinceEpoch}',
            'type': 'log',
            'data': {
              'cpf': cpf,
              'person_name': personName,
              'timestamp': timestamp.toIso8601String(),
              'confidence': confidence,
              'tipo': tipo,
              'operador_nome': operadorNome ?? '',
              'colegio': colegio ?? '',
              'turma': turma ?? '',
              'inicio_viagem': inicioViagem ?? '',
              'fim_viagem': fimViagem ?? '',
            }
          },
          if (tipoNormalizado.isNotEmpty &&
              tipoNormalizado != 'RECONHECIMENTO' &&
              tipoNormalizado != 'FACIAL')
            {
              'id': 'mov_immediate_${DateTime.now().millisecondsSinceEpoch}',
              'type': 'movimentacao',
              'data': {
                'cpf': cpf,
                'nome': personName,
                'movimentacao': tipoNormalizado,
                'operador': operadorNome ?? '',
              }
            },
        ]);
        print('✅ [FirebaseService] Log enviado via API: $personName - $tipo');
      }
    } catch (e) {
      print('⚠️ [FirebaseService] Erro ao enviar log via API, ficará pendente: $e');
      // O log ficará marcado como não sincronizado e será enviado no próximo ciclo
    }
  }

  Future<void> queueCadastroFacial({
    required String cpf,
    required String nome,
    required String email,
    required String telefone,
    required List<double> embedding,
    required String personId,
    String? colegio,
    String? turma,
    String? inicioViagem,
    String? fimViagem,
  }) async {
    final cpfLimpo = cpf.trim();

    // Buscar movimentação atual do aluno
    final db = await _db.database;
    final alunoExistente = await db.query(
      'alunos',
      columns: ['movimentacao'],
      where: 'cpf = ?',
      whereArgs: [cpfLimpo],
      limit: 1,
    );

    final movimentacaoAtual = alunoExistente.isNotEmpty
        ? (alunoExistente.first['movimentacao']?.toString() ?? 'QUARTO')
        : 'QUARTO';

    // Atualizar localmente primeiro
    await db.insert(
      'alunos',
      {
        'cpf': cpfLimpo,
        'nome': nome,
        'colegio': colegio ?? '',
        'turma': turma ?? '',
        'email': email,
        'telefone': telefone,
        'embedding': '[${embedding.join(',')}]',
        'facial_cadastrada': 1,
        'data_cadastro_facial': DateTime.now().toIso8601String(),
        'movimentacao': movimentacaoAtual,
        'inicio_viagem': inicioViagem ?? '',
        'fim_viagem': fimViagem ?? '',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Tentar enviar via API REST
    try {
      if (_api.isAuthenticated && await _hasInternet()) {
        await _api.uploadBatch([
          {
            'id': 'face_${cpfLimpo}_${DateTime.now().millisecondsSinceEpoch}',
            'type': 'embedding',
            'data': {
              'cpf': cpfLimpo,
              'embedding': embedding,
            }
          }
        ]);
        print('✅ [FirebaseService] Cadastro facial enviado via API: $nome');
      } else {
        throw Exception('API não disponível');
      }
    } catch (e) {
      print('⚠️ [FirebaseService] Erro ao enviar cadastro facial via API: $e');
      // Enfileirar para retry
      await _db.enqueueOutbox('face_register', {
        'cpf': cpfLimpo,
        'nome': nome,
        'colegio': colegio ?? '',
        'turma': turma ?? '',
        'email': email,
        'telefone': telefone,
        'embedding': embedding,
        'personId': personId,
        'movimentacao': movimentacaoAtual,
        'inicio_viagem': inicioViagem ?? '',
        'fim_viagem': fimViagem ?? '',
      });
    }
  }

  // =============================
  // SINCRONIZAÇÃO EM BACKGROUND
  // =============================

  Future<void> trySyncInBackground() async {
    if (_isSyncing) {
      print('⏭️ [FirebaseService] Sincronização já em andamento, pulando');
      return;
    }

    _isSyncing = true;
    isSyncingNotifier.value = true;

    try {
      if (await _hasInternet()) {
        // PASSO 1: Enviar pendências locais
        await _uploadPending();
        
        // PASSO 2: Baixar delta do servidor
        await _syncDelta();
      }
    } catch (e) {
      print('❌ [FirebaseService] Erro na sincronização em background: $e');
      Sentry.captureException(e);
    } finally {
      _isSyncing = false;
      isSyncingNotifier.value = false;
    }
  }

  // =============================
  // OPERAÇÕES ADMINISTRATIVAS
  // =============================

  Future<void> encerrarViagem({String? inicioViagem, String? fimViagem}) async {
    try {
      print('🔚 [FirebaseService] Encerramento de viagem solicitado');
      // O encerramento agora é feito via API REST (o backend cuida do Firestore)
      // Aqui apenas limpamos os dados locais
      final db = await _db.database;
      
      if (inicioViagem != null && fimViagem != null) {
        await db.delete('alunos', where: 'inicio_viagem = ? AND fim_viagem = ?', whereArgs: [inicioViagem, fimViagem]);
        await db.delete('logs', where: 'inicio_viagem = ? AND fim_viagem = ?', whereArgs: [inicioViagem, fimViagem]);
        print('✅ [FirebaseService] Dados locais da viagem $inicioViagem-$fimViagem limpos');
      } else {
        await db.delete('alunos');
        await db.delete('logs');
        print('✅ [FirebaseService] Todos os dados locais de viagens limpos');
      }
    } catch (e) {
      print('❌ [FirebaseService] Erro ao encerrar viagem: $e');
      Sentry.captureException(e);
      rethrow;
    }
  }

  Future<void> enviarTodosParaQuarto() async {
    try {
      final db = await _db.database;
      await db.update('alunos', {'movimentacao': 'QUARTO'});
      
      // Enfileirar para o backend processar
      // O sync delta cuidará de atualizar o Firestore via backend
      print('✅ [FirebaseService] Todos os alunos locais marcados como QUARTO');
    } catch (e) {
      print('❌ [FirebaseService] Erro ao enviar todos para quarto: $e');
      Sentry.captureException(e);
      rethrow;
    }
  }

  Future<List<Map<String, String>>> listarViagens() async {
    try {
      final db = await _db.database;
      final alunos = await db.query('alunos');
      final viagensSet = <String>{};

      for (var aluno in alunos) {
        final inicio = aluno['inicio_viagem'] as String? ?? '';
        final fim = aluno['fim_viagem'] as String? ?? '';
        if (inicio.isNotEmpty && fim.isNotEmpty) {
          viagensSet.add('$inicio|$fim');
        }
      }

      return viagensSet.map((v) {
        final parts = v.split('|');
        return {
          'inicio_viagem': parts[0],
          'fim_viagem': parts[1],
        };
      }).toList();
    } catch (e) {
      print('❌ [FirebaseService] Erro ao listar viagens: $e');
      Sentry.captureException(e);
      return [];
    }
  }

  // =============================
  // OPERAÇÕES DE EMBARQUE
  // =============================

  /// Registra embarque/retorno.
  ///
  /// OFFLINE-FIRST: a marcação é gravada na tabela local `embarques` e numa fila
  /// durável (`sync_queue`, tipo 'embarque') na MESMA transação. O envio ao
  /// servidor acontece em `_uploadPending`, sempre que houver internet e token.
  /// Antes, sem internet a marcação nunca era enviada e se perdia.
  Future<void> atualizarEmbarque({
    required String cpf,
    required String idPasseio,
    required String onibus,
    String? embarque,
    String? retorno,
  }) async {
    try {
      final cpfLimpo = cpf.trim();
      if (cpfLimpo.isEmpty) return;

      final eventAt = _nowIsoUtc();
      final db = await _db.database;

      await db.transaction((txn) async {
        final updateData = <String, dynamic>{};
        if (embarque != null) updateData['embarque'] = embarque;
        if (retorno != null) updateData['retorno'] = retorno;
        if (updateData.isNotEmpty) {
          await txn.update('embarques', updateData, where: 'cpf = ?', whereArgs: [cpfLimpo]);
        }

        final campos = <String, String>{
          if (embarque != null) 'embarque': embarque,
          if (retorno != null) 'retorno': retorno,
        };
        for (final entry in campos.entries) {
          await txn.insert('sync_queue', {
            'tipo': _tipoEmbarque,
            'payload': jsonEncode({
              'cpf': cpfLimpo,
              'campo': entry.key,
              'valor': entry.value,
              'event_at': eventAt,
              if (onibus.trim().isNotEmpty) 'onibus': onibus.trim(),
              if (idPasseio.trim().isNotEmpty) 'idPasseio': idPasseio.trim(),
            }),
            'created_at': eventAt,
          });
        }
      });

      print('💾 [FirebaseService] Embarque registrado na fila local: $cpfLimpo');

      // Tenta enviar já, sem bloquear a tela. Se estiver offline, fica na fila.
      unawaited(trySyncInBackground());
    } catch (e) {
      print('❌ [FirebaseService] Erro ao registrar embarque: $e');
      Sentry.captureException(e);
      rethrow;
    }
  }

  static const String _tipoEmbarque = 'embarque';

  /// ISO-8601 em UTC com precisão de milissegundos (comparável no servidor).
  String _nowIsoUtc() => DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ).toIso8601String();

  /// Converte o timestamp gravado no log (hora local, sem fuso) para UTC.
  String? _paraIsoUtc(Object? valor) {
    final dt = DateTime.tryParse((valor ?? '').toString());
    if (dt == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(dt.millisecondsSinceEpoch, isUtc: true)
        .toIso8601String();
  }

  /// Movimentação local dos alunos que têm leituras ainda não enviadas.
  /// O delta do servidor não pode sobrescrever esse estado mais recente.
  Future<Map<String, String>> _movimentacoesPendentes(Database db) async {
    // Instalações muito antigas podem ter `logs` sem a coluna sincronizado:
    // nesse caso segue sem a proteção, mas sem derrubar o delta inteiro.
    final List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery('''
      SELECT cpf, movimentacao FROM alunos
      WHERE cpf IN (
        SELECT DISTINCT cpf FROM logs
        WHERE sincronizado = 0
          AND UPPER(TRIM(tipo)) NOT IN ('RECONHECIMENTO', 'FACIAL')
      )
    ''');
    } catch (e) {
      print('⚠️ [FirebaseService] Não foi possível ler movimentações pendentes: $e');
      return {};
    }
    return {
      for (final r in rows)
        if (r['cpf'] != null && r['movimentacao'] != null)
          r['cpf'].toString(): r['movimentacao'].toString(),
    };
  }

  /// Marcações de embarque/retorno ainda não confirmadas pelo servidor,
  /// por CPF (a mais recente de cada campo). Usado para que dados vindos do
  /// servidor não apaguem marcações feitas offline.
  Future<Map<String, Map<String, String>>> getEmbarquesPendentes() async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_queue',
      where: 'tipo = ?',
      whereArgs: [_tipoEmbarque],
      orderBy: 'id ASC',
    );
    final pendentes = <String, Map<String, String>>{};
    for (final row in rows) {
      try {
        final p = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
        final cpf = (p['cpf'] ?? '').toString();
        final campo = (p['campo'] ?? '').toString();
        if (cpf.isEmpty || campo.isEmpty) continue;
        pendentes.putIfAbsent(cpf, () => {})[campo] = (p['valor'] ?? '').toString();
      } catch (_) {}
    }
    return pendentes;
  }

  Future<List<Map<String, dynamic>>> buscarEmbarques({
    required String idPasseio,
    String? onibus,
  }) async {
    // 1. Tentar a API. Falha de rede (Wi-Fi sem internet, timeout) NÃO pode
    //    devolver lista vazia — antes isso apagava a lista salva no celular.
    List<Map<String, dynamic>>? lista;
    try {
      if (_api.isAuthenticated && await _hasInternet()) {
        final response = await _api.getEmbarquesPorViagem(
          idPasseio: idPasseio,
          onibus: onibus,
        );
        if (response['success'] == true) {
          lista = List<Map<String, dynamic>>.from(response['data'] ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (e) {
      print('⚠️ [FirebaseService] API de embarques indisponível, usando dados locais: $e');
    }

    try {
      // 2. Fallback: SQLite local (colunas snake_case → formato da API)
      final List<Map<String, dynamic>> resultado =
          lista ?? await _buscarEmbarquesLocais(idPasseio: idPasseio, onibus: onibus);

      // 3. Marcações offline ainda não enviadas prevalecem sobre o servidor
      final pendentes = await getEmbarquesPendentes();
      if (pendentes.isNotEmpty) {
        for (final item in resultado) {
          final pendente = pendentes[(item['cpf'] ?? '').toString()];
          if (pendente != null) item.addAll(pendente);
        }
      }
      return resultado;
    } catch (e) {
      print('❌ [FirebaseService] Erro ao buscar embarques: $e');
      Sentry.captureException(e);
      rethrow; // DataService mantém a lista salva localmente
    }
  }

  Future<List<Map<String, dynamic>>> _buscarEmbarquesLocais({
    required String idPasseio,
    String? onibus,
  }) async {
    final db = await _db.database;
    String where = 'id_passeio = ?';
    final whereArgs = <dynamic>[idPasseio];
    if (onibus != null) {
      where += ' AND onibus = ?';
      whereArgs.add(onibus);
    }
    final rows = await db.query('embarques', where: where, whereArgs: whereArgs);
    return rows
            .map((r) => <String, dynamic>{
                  'cpf': r['cpf'],
                  'nome': r['nome'],
                  'colegio': r['colegio'],
                  'turma': r['turma'],
                  'idPasseio': r['id_passeio'],
                  'onibus': r['onibus'],
                  'inicioViagem': r['inicio_viagem'],
                  'fimViagem': r['fim_viagem'],
                  'embarque': r['embarque'],
                  'retorno': r['retorno'],
                  'facial_cadastrada': r['facial_cadastrada'] == 1,
                })
            .toList();
  }

  // =============================
  // UTILITÁRIOS
  // =============================

  Future<bool> _hasInternet() async {
    final c = await Connectivity().checkConnectivity();
    return c != ConnectivityResult.none;
  }
}
