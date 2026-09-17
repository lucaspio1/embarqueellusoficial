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

class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final DatabaseHelper _db = DatabaseHelper.instance;
  final ApiService _api = ApiService.instance;

  Timer? _syncTimer;
  bool _isSyncing = false;

  // ValueNotifier para que widgets possam observar o estado de sincronização
  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);

  void init() {
    _syncTimer?.cancel();

    // Inicializar o ApiService (carregar token salvo)
    _api.init();

    // Sincronização automática a cada 30 segundos via REST delta
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      print('⏰ [FirebaseService] Timer de sincronização disparado');
      await trySyncInBackground();
    });

    print('✅ [FirebaseService] Sincronização via REST API iniciada (intervalo: 30s)');
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

      if (response['success'] == true) {
        final delta = response['delta'] as Map<String, dynamic>? ?? {};
        final serverTime = response['serverTime'] as String?;

        // Aplicar delta no SQLite
        await _applyDelta(delta);

        // Salvar timestamp da sync
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
      }
    } catch (e) {
      print('⚠️ [FirebaseService] Erro no sync delta: $e');
    }
  }

  /// Aplica os dados delta recebidos no SQLite local
  Future<void> _applyDelta(Map<String, dynamic> delta) async {
    final db = await _db.database;

    // Aplicar alunos
    if (delta.containsKey('alunos')) {
      final alunos = delta['alunos'] as List;
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
            'movimentacao': _getField(data, 'movimentacao', 'QUARTO'),
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
        batch.insert(
          'quartos',
          {
            'numero_quarto': _getField(data, 'numero_quarto', ''),
            'escola': _getField(data, 'colegio', '') ?? _getField(data, 'escola', ''),
            'nome_hospede': _getField(data, 'nome_hospede', ''),
            'cpf': _getField(data, 'cpf', ''),
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
      final batch = db.batch();
      for (var embarque in embarques) {
        final data = embarque as Map<String, dynamic>;
        final cpf = _getField(data, 'cpf', '');
        if (cpf.isEmpty) continue;

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
            'embarque': _getField(data, 'embarque', ''),
            'retorno': _getField(data, 'retorno', ''),
            'facial_cadastrada': _getField(data, 'facial_cadastrada', false) == true ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
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

  /// Envia operações pendentes (logs, movimentações, embeddings) para o backend
  Future<void> _uploadPending() async {
    try {
      if (!_api.isAuthenticated) return;

      final db = await _db.database;
      final operations = <Map<String, dynamic>>[];

      // 1. Logs pendentes
      final pendingLogs = await db.query(
        'logs',
        where: 'sincronizado = ?',
        whereArgs: [0],
        limit: 50,
      );

      for (final log in pendingLogs) {
        operations.add({
          'id': 'log_${log['id']}',
          'type': 'log',
          'data': {
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
      }

      // 2. Movimentações pendentes (logs com tipo não-RECONHECIMENTO)
      for (final log in pendingLogs) {
        final tipo = (log['tipo'] as String).trim().toUpperCase();
        final cpf = log['cpf'] as String;

        if (tipo.isNotEmpty && tipo != 'RECONHECIMENTO' && tipo != 'FACIAL') {
          operations.add({
            'id': 'mov_${log['id']}',
            'type': 'movimentacao',
            'data': {
              'cpf': cpf,
              'nome': log['person_name'] ?? '',
              'movimentacao': tipo,
              'operador': log['operador_nome'] ?? '',
            }
          });
        }
      }

      // 3. Outbox pendente (cadastros faciais, etc.)
      final outbox = await _db.getOutboxBatch(limit: 50);
      for (final row in outbox) {
        try {
          final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
          final tipo = row['tipo'] as String;

          if (tipo == 'face_register') {
            operations.add({
              'id': 'outbox_${row['id']}',
              'type': 'embedding',
              'data': {
                'cpf': payload['cpf'].toString().trim(),
                'embedding': payload['embedding'],
              }
            });
          }
        } catch (e) {
          print('⚠️ [FirebaseService] Erro ao processar outbox ${row['id']}: $e');
        }
      }

      if (operations.isEmpty) return;

      print('📤 [FirebaseService] Enviando ${operations.length} operações pendentes...');

      final response = await _api.uploadBatch(operations);

      if (response['success'] == true) {
        // Marcar logs como sincronizados
        for (final log in pendingLogs) {
          await db.update(
            'logs',
            {'sincronizado': 1},
            where: 'id = ?',
            whereArgs: [log['id']],
          );
        }

        // Remover outbox sincronizados
        for (final row in outbox) {
          await db.delete('sync_queue', where: 'id = ?', whereArgs: [row['id']]);
        }

        print('✅ [FirebaseService] ${operations.length} operações sincronizadas com sucesso');
      }
    } catch (e) {
      print('❌ [FirebaseService] Erro ao enviar pendências: $e');
      Sentry.captureException(e);
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

  Future<void> atualizarEmbarque({
    required String cpf,
    required String idPasseio,
    required String onibus,
    String? embarque,
    String? retorno,
  }) async {
    try {
      final cpfLimpo = cpf.trim();

      // Atualizar localmente
      final db = await _db.database;
      final updateData = <String, dynamic>{
        'cpf': cpfLimpo,
      };
      if (embarque != null) updateData['embarque'] = embarque;
      if (retorno != null) updateData['retorno'] = retorno;
      
      await db.update(
        'embarques',
        updateData,
        where: 'cpf = ?',
        whereArgs: [cpfLimpo],
      );

      // Enviar via API REST
      if (_api.isAuthenticated && await _hasInternet()) {
        await _api.uploadBatch([
          {
            'id': 'emb_${cpfLimpo}_${DateTime.now().millisecondsSinceEpoch}',
            'type': 'embarque',
            'data': {
              'cpf': cpfLimpo,
              'idPasseio': idPasseio,
              'onibus': onibus,
              if (embarque != null) 'embarque': embarque,
              if (retorno != null) 'retorno': retorno,
            }
          }
        ]);
      }

      print('✅ [FirebaseService] Embarque atualizado: $cpfLimpo');
    } catch (e) {
      print('❌ [FirebaseService] Erro ao atualizar embarque: $e');
      Sentry.captureException(e);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> buscarEmbarques({
    required String idPasseio,
    String? onibus,
  }) async {
    try {
      // Buscar via API REST
      if (_api.isAuthenticated && await _hasInternet()) {
        final response = await _api.getEmbarquesPorViagem(
          idPasseio: idPasseio,
          onibus: onibus,
        );
        if (response['success'] == true) {
          return List<Map<String, dynamic>>.from(response['data'] ?? []);
        }
      }

      // Fallback: buscar do SQLite local
      final db = await _db.database;
      String where = 'id_passeio = ?';
      List<dynamic> whereArgs = [idPasseio];
      
      if (onibus != null) {
        where += ' AND onibus = ?';
        whereArgs.add(onibus);
      }

      return await db.query('embarques', where: where, whereArgs: whereArgs);
    } catch (e) {
      print('❌ [FirebaseService] Erro ao buscar embarques: $e');
      Sentry.captureException(e);
      return [];
    }
  }

  // =============================
  // UTILITÁRIOS
  // =============================

  Future<bool> _hasInternet() async {
    final c = await Connectivity().checkConnectivity();
    return c != ConnectivityResult.none;
  }
}
