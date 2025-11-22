// lib/services/offline_sync_service.dart — VERSÃO CONSOLIDADA (FASE 1)
// Serviço principal de sincronização que unifica Users, Alunos, Logs e Outbox
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/config/app_config.dart';
import 'package:embarqueellus/models/evento.dart';
import 'package:embarqueellus/services/quartos_sync_service.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  final DatabaseHelper _db = DatabaseHelper.instance;

  // URL lida do arquivo .env
  String get _sheetsWebhook => AppConfig.instance.googleAppsScriptUrl;

  Timer? _syncTimer;
  bool _isSyncing = false; // Lock para evitar sincronizações simultâneas

  void init() {
    _syncTimer?.cancel();

    _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      print('⏰ [OfflineSync] Timer de sincronização disparado');
      await trySyncInBackground();
    });

    print('✅ [OfflineSync] Sincronização automática iniciada (a cada 1 minuto)');
    trySyncInBackground();
    syncEmbeddingsFromServer();
  }

  // -----------------------------
  // Enfileiramento
  // -----------------------------

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

    await _db.enqueueOutbox('movement_log', {
      'cpf': cpf,
      'personName': personName,
      'colegio': colegio ?? '',
      'turma': turma ?? '',
      'timestamp': timestamp.toIso8601String(),
      'confidence': confidence,
      'personId': personId,
      'tipo': tipo,
      'operadorNome': operadorNome,
      'inicio_viagem': inicioViagem ?? '',
      'fim_viagem': fimViagem ?? '',
    });

    print('📝 [OfflineSync] Log enfileirado: $personName - $tipo - Colégio: ${colegio ?? "N/A"}, Turma: ${turma ?? "N/A"} (Operador: ${operadorNome ?? "N/A"})');
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
    // Buscar movimentação atual da pessoa (preserva a existente, não força QUARTO)
    final db = await _db.database;
    final pessoaExistente = await db.query(
      'pessoas_facial',
      columns: ['movimentacao'],
      where: 'cpf = ?',
      whereArgs: [cpf],
      limit: 1,
    );

    final movimentacaoAtual = pessoaExistente.isNotEmpty
        ? (pessoaExistente.first['movimentacao']?.toString() ?? 'QUARTO')
        : 'QUARTO';

    await _db.enqueueOutbox('face_register', {
      'cpf': cpf,
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

    print('📝 [OfflineSync] Cadastro facial enfileirado: $nome - Colégio: ${colegio ?? "N/A"}, Turma: ${turma ?? "N/A"} (Movimentação atual: $movimentacaoAtual, Viagem: ${inicioViagem ?? "N/A"} a ${fimViagem ?? "N/A"})');
  }

  Future<bool> _hasInternet() async {
    final c = await Connectivity().checkConnectivity();
    return c != ConnectivityResult.none;
  }

  Future<bool> trySyncNow() async {
    if (!await _hasInternet()) {
      print('📵 [OfflineSync] Sem conexão com internet');
      return false;
    }

    if (_sheetsWebhook.isEmpty) {
      print('⚠️ [OfflineSync] URL do webhook não configurada');
      return false;
    }

    final batch = await _db.getOutboxBatch(limit: 50);
    if (batch.isEmpty) {
      print('✅ [OfflineSync] Fila vazia, nada para sincronizar');
      return true;
    }

    print('📤 [OfflineSync] Sincronizando ${batch.length} itens...');
    final faceRegisters = <Map<String, dynamic>>[];
    final movementLogs = <Map<String, dynamic>>[];

    for (final row in batch) {
      final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      payload['idOutbox'] = row['id'];
      if (row['tipo'] == 'face_register') {
        faceRegisters.add(payload);
      } else {
        movementLogs.add(payload);
      }
    }

    final successIds = <int>[];

    try {
      if (faceRegisters.isNotEmpty) {
        print('📸 [OfflineSync] Enviando ${faceRegisters.length} cadastro(s) facial(is)...');
        for (final item in faceRegisters) {
          final ok = await _sendPersonIndividually(item);
          if (ok) {
            final id = (item['idOutbox'] as int?) ?? -1;
            if (id != -1) successIds.add(id);
          }
        }
      }

      if (movementLogs.isNotEmpty) {
        print('📍 [OfflineSync] Tentando envio em LOTE de ${movementLogs.length} movimentação(ões)...');
        final lot = await _sendMovementsBatch(movementLogs);

        if (lot.allSucceeded) {
          successIds.addAll(
            movementLogs.map((m) => (m['idOutbox'] as int?) ?? -1).where((id) => id != -1),
          );
          print('✅ [OfflineSync] Lote de movimentações confirmado');
        } else {
          print('⚠️ [OfflineSync] Lote parcial — fallback individual...');
          for (final item in lot.notConfirmedItems) {
            final ok = await _sendMovementIndividually(item);
            if (ok) {
              final id = (item['idOutbox'] as int?) ?? -1;
              if (id != -1) successIds.add(id);
            }
          }
        }
      }

      if (successIds.isNotEmpty) {
        await _db.deleteOutboxIds(successIds);
        print('🗑️ [OfflineSync] Removidos ${successIds.length} item(ns) enviados');
      }

      final pending = batch.length - successIds.length;
      if (pending == 0) {
        print('✅ [OfflineSync] Sincronização concluída com sucesso');
        return true;
      } else {
        print('⚠️ [OfflineSync] ${pending} item(ns) ainda na fila');
        return false;
      }
    } catch (e) {
      print('❌ [OfflineSync] Erro na sincronização: $e');
      return false;
    }
  }

  // -----------------------------
  // Background sem isolate!
  // -----------------------------

  Future<void> trySyncInBackground() async {
    try {
      // Sincroniza TUDO: usuários, alunos, pessoas, logs, eventos E outbox
      await syncAll();
    } catch (e) {
      print('❌ [OfflineSync] Erro em background: $e');
    }
  }

  // -----------------------------
  // Envio — Movimentações
  // -----------------------------

  Future<_BatchResult> _sendMovementsBatch(List<Map<String, dynamic>> items) async {
    final body = <String, dynamic>{
      'action': 'addMovementLog',
      'people': items.map((m) {
        final c = Map<String, dynamic>.from(m);
        c.remove('idOutbox');
        return c;
      }).toList(),
    };

    final resp = await _postWithRedirectTolerance(body);
    if (resp == null) {
      return _BatchResult(allSucceeded: false, notConfirmedItems: items);
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      try {
        final json = jsonDecode(resp.body);
        final success = json is Map && json['success'] == true;
        if (!success) {
          print('⚠️ [OfflineSync] 2xx porém success=false: ${resp.body}');
          return _BatchResult(allSucceeded: false, notConfirmedItems: items);
        }
        final data = (json['data'] as Map?) ?? const {};
        final total = (data['total'] as num?)?.toInt() ?? -1;
        if (total == items.length) {
          return _BatchResult(allSucceeded: true, notConfirmedItems: const []);
        }
        print('ℹ️ [OfflineSync] Lote parcial: total=$total de ${items.length}');
        return _BatchResult(allSucceeded: false, notConfirmedItems: items);
      } catch (_) {
        return _BatchResult(allSucceeded: true, notConfirmedItems: const []);
      }
    }

    print('❌ [OfflineSync] Falha lote HTTP ${resp.statusCode}: ${resp.body}');
    return _BatchResult(allSucceeded: false, notConfirmedItems: items);
  }

  Future<bool> _sendMovementIndividually(Map<String, dynamic> item) async {
    final copy = Map<String, dynamic>.from(item)..remove('idOutbox');
    final body = <String, dynamic>{'action': 'addMovementLog', 'people': [copy]};
    print('📤 [OfflineSync] Enviando movimento com dados: CPF=${copy['cpf']}, Nome=${copy['personName']}, Colégio=${copy['colegio']}, Tipo=${copy['tipo']}');
    return _postWithRetriesAndSuccess(body);
  }

  // -----------------------------
  // Envio — Cadastros faciais
  // -----------------------------

  Future<bool> _sendPersonIndividually(Map<String, dynamic> item) async {
    final copy = Map<String, dynamic>.from(item)..remove('idOutbox');

    final body = <String, dynamic>{
      'action': 'addPessoa',
      'cpf': copy['cpf'],
      'nome': copy['nome'],
      'colegio': copy['colegio'] ?? '',
      'turma': copy['turma'] ?? '',
      'email': copy['email'] ?? '',
      'telefone': copy['telefone'] ?? '',
      'embedding': copy['embedding'],
      'personId': copy['personId'] ?? copy['cpf'],
      'movimentacao': copy['movimentacao'] ?? 'QUARTO',
      'inicio_viagem': copy['inicio_viagem'] ?? '',
      'fim_viagem': copy['fim_viagem'] ?? '',
    };
    return _postWithRetriesAndSuccess(body);
  }

  Future<bool> _postWithRetriesAndSuccess(Map<String, dynamic> body, {int maxRetries = 3}) async {
    int attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      try {
        final resp = await _postWithRedirectTolerance(body);
        if (resp == null) {
          print('⚠️ [OfflineSync] Sem resposta (tentativa $attempt/$maxRetries)');
        } else {
          print('📡 [OfflineSync] Status: ${resp.statusCode} (tentativa $attempt/$maxRetries)');

          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            try {
              final json = jsonDecode(resp.body);
              if (json is Map && json['success'] == true) return true;
              return true;
            } catch (_) {
              return true;
            }
          }

          print('❌ [OfflineSync] Falha HTTP ${resp.statusCode}: ${resp.body}');
        }
      } catch (e) {
        print('❌ [OfflineSync] Exceção ao enviar: $e (tentativa $attempt/$maxRetries)');
      }
      await Future.delayed(Duration(seconds: attempt));
    }
    return false;
  }

  Future<http.Response?> _postWithRedirectTolerance(Map<String, dynamic> body) async {
    print('🌐 [OfflineSync] POST -> $_sheetsWebhook | action=${body['action']}');
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse(_sheetsWebhook));
      req.followRedirects = false;
      req.headers['Content-Type'] = 'application/json; charset=utf-8';
      req.headers['Accept'] = 'application/json';
      req.headers['User-Agent'] = 'Flutter-App/1.0';
      req.body = jsonEncode(body);

      final streamed = await client.send(req);
      final resp = await http.Response.fromStream(streamed);

      final preview = resp.body.length > 300 ? '${resp.body.substring(0, 300)}...' : resp.body;
      print('📥 [OfflineSync] Resp ${resp.statusCode} | body: $preview');

      // Tratar redirecionamento 302
      if (resp.statusCode == 302 && resp.headers['location'] != null) {
        final redirectedUrl = resp.headers['location']!;
        print('🔁 [OfflineSync] Seguindo redirect: $redirectedUrl');

        try {
          // Tentar POST primeiro
          http.Response redirectedResponse = await http.post(
            Uri.parse(redirectedUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'Flutter-App/1.0',
            },
            body: jsonEncode(body),
          );

          // Se POST não funcionar (405), tentar GET
          if (redirectedResponse.statusCode == 405) {
            print('⚠️ [OfflineSync] POST não permitido, tentando GET...');
            redirectedResponse = await http.get(
              Uri.parse(redirectedUrl),
              headers: {
                'Accept': 'application/json',
                'User-Agent': 'Flutter-App/1.0',
              },
            );
          }

          print('📡 [OfflineSync] Redirect Status: ${redirectedResponse.statusCode}');
          return redirectedResponse;
        } catch (e) {
          print('❌ [OfflineSync] Erro ao seguir redirect: $e');
          return resp; // Retorna resposta original em caso de erro
        }
      }

      return resp;
    } catch (e) {
      print('❌ [OfflineSync] Erro ao enviar POST: $e');
      return null;
    } finally {
      client.close();
    }
  }

  // -----------------------------
  // Download de embeddings do servidor
  // -----------------------------

  Future<void> syncEmbeddingsFromServer() async {
    print("🔄 [Embeddings] Buscando embeddings do servidor...");
    try {
      final resp = await http.post(
        Uri.parse(_sheetsWebhook),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"action": "getAllPeople"}),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = jsonDecode(resp.body);
        if (body is Map && body["success"] == true) {
          final List<dynamic> pessoas = (body["data"] as List?) ?? const [];
          int count = 0;

          for (final p in pessoas) {
            if (p is Map && p["cpf"] != null && p["embedding"] != null) {
              await _db.insertEmbedding({
                "cpf": p["cpf"],
                "nome": p["nome"] ?? "",
                "embedding": p["embedding"],
              });
              await _db.updateAlunoFacial(p["cpf"].toString(), "CADASTRADA");
              count++;
            }
          }
          print("✅ [Embeddings] $count embeddings sincronizados com sucesso!");
        } else {
          print("⚠️ [Embeddings] Resposta sem success=true: ${resp.body}");
        }
      } else {
        print("❌ [Embeddings] HTTP ${resp.statusCode}: ${resp.body}");
      }
    } catch (e) {
      print("❌ [Embeddings] Erro ao buscar embeddings: $e");
    }
  }

  Future<void> testConnection() async {
    print('🔍 [OfflineSync] Testando conexão...');
    final ok = await _postWithRetriesAndSuccess({
      'action': 'testConnection',
      'people': [
        {'timestamp': DateTime.now().toIso8601String()}
      ],
    });
    if (ok) {
      print('✅ [OfflineSync] Teste OK');
    } else {
      print('❌ [OfflineSync] Teste falhou');
    }
  }

  // ====================================================================
  // FASE 1: SINCRONIZAÇÃO CONSOLIDADA
  // ====================================================================
  // Métodos para sincronizar TUDO de uma vez (Users, Alunos, Logs, Outbox)
  // Mantém compatibilidade com serviços específicos (facades)
  // ====================================================================

  /// Sincroniza TUDO: Usuários, Alunos, Pessoas, Logs e Outbox
  /// ✅ OTIMIZADO: Usa Batching HTTP + Delta Sync
  /// Retorna resultado consolidado com estatísticas de cada tipo
  Future<ConsolidatedSyncResult> syncAll() async {
    // Evitar sincronizações simultâneas
    if (_isSyncing) {
      print('⏸️ [OfflineSync] Sincronização já em andamento, pulando...');
      return ConsolidatedSyncResult();
    }

    _isSyncing = true;
    print('🔄 [OfflineSync] Iniciando sincronização completa...');

    final results = ConsolidatedSyncResult();

    // Verificar conectividade
    if (!await _hasInternet()) {
      print('📵 [OfflineSync] Sem conexão com internet');
      results.hasInternet = false;
      _isSyncing = false; // Liberar lock
      return results;
    }

    // ✅ OTIMIZAÇÃO 1: BATCHING HTTP - Enviar todas as requisições em um único request
    // ✅ OTIMIZAÇÃO 2: DELTA SYNC - Buscar apenas mudanças desde a última sync
    try {
      print('🚀 [OfflineSync] Usando BATCHING HTTP + DELTA SYNC');

      // Buscar timestamps da última sincronização
      final prefs = await SharedPreferences.getInstance();
      final lastSyncUsers = prefs.getString('last_sync_users');
      final lastSyncPeople = prefs.getString('last_sync_people');
      final lastSyncStudents = prefs.getString('last_sync_students');
      final lastSyncLogs = prefs.getString('last_sync_logs');
      final lastSyncEventos = prefs.getString('last_sync_eventos');

      // Montar requisição em batch
      final batchBody = {
        'action': 'batchSync',
        'requests': [
          {
            'action': 'getAllUsers',
            if (lastSyncUsers != null) 'since': lastSyncUsers,
          },
          {
            'action': 'getAllPeople',
            if (lastSyncPeople != null) 'since': lastSyncPeople,
          },
          {
            'action': 'getAllStudents',
            if (lastSyncStudents != null) 'since': lastSyncStudents,
          },
          {
            'action': 'getAllLogs',
            if (lastSyncLogs != null) 'since': lastSyncLogs,
          },
          {
            'action': 'getQuartos',
          },
          {
            'action': 'getEventos',
            if (lastSyncEventos != null) 'timestamp': lastSyncEventos,
          },
        ],
      };

      print('📤 [OfflineSync] Enviando batch com ${batchBody['requests']?.length} requisições...');
      if (lastSyncPeople != null) {
        print('🔄 [DeltaSync] Última sync de pessoas: $lastSyncPeople');
      }

      // Enviar requisição única em batch
      final response = await _postWithRedirectTolerance(batchBody);

      if (response == null || response.statusCode != 200) {
        print('❌ [OfflineSync] Falha no batch sync: ${response?.statusCode}');
        _isSyncing = false;
        return results;
      }

      final batchResponse = jsonDecode(response.body);

      if (batchResponse['success'] != true) {
        print('❌ [OfflineSync] Batch sync retornou success=false');
        _isSyncing = false;
        return results;
      }

      final responses = batchResponse['data']['responses'] as List;
      final syncTimestamp = DateTime.now().toIso8601String();

      print('✅ [OfflineSync] Batch recebido com ${responses.length} respostas');

      // Processar cada resposta do batch
      for (final item in responses) {
        final action = item['action'] as String;
        final success = item['success'] as bool;
        final data = item['data'];

        print('📥 [OfflineSync] Processando resposta: $action (success: $success)');

        if (!success) {
          print('⚠️ [OfflineSync] $action falhou: ${item['error']}');
          continue;
        }

        try {
          switch (action) {
            case 'getAllUsers':
              final userResult = await _processUsersResponse(data);
              results.users = userResult;
              if (userResult.success) {
                await prefs.setString('last_sync_users', syncTimestamp);
              }
              break;

            case 'getAllPeople':
              final pessoasResult = await _processPessoasResponse(data);
              results.pessoas = pessoasResult;
              if (pessoasResult.success) {
                await prefs.setString('last_sync_people', syncTimestamp);
                FaceRecognitionService.instance.invalidateCache();
              }
              break;

            case 'getAllStudents':
              final alunosResult = await _processAlunosResponse(data);
              results.alunos = alunosResult;
              if (alunosResult.success) {
                await prefs.setString('last_sync_students', syncTimestamp);
              }
              break;

            case 'getAllLogs':
              final logsResult = await _processLogsResponse(data);
              results.logs = logsResult;
              if (logsResult.success) {
                await prefs.setString('last_sync_logs', syncTimestamp);
              }
              break;

            case 'getQuartos':
              final quartosResult = await _processQuartosResponse(data);
              results.quartos = quartosResult;
              break;

            case 'getEventos':
              final eventosResult = await _processEventosResponse(data);
              results.eventos = eventosResult;
              if (eventosResult.success) {
                await prefs.setString('last_sync_eventos', syncTimestamp);
              }
              break;

            default:
              print('⚠️ [OfflineSync] Ação desconhecida no batch: $action');
          }
        } catch (e) {
          print('❌ [OfflineSync] Erro ao processar $action: $e');
        }
      }

      print('✅ [OfflineSync] Batch sync processado com sucesso');

    } catch (e) {
      print('❌ [OfflineSync] Erro no batch sync: $e');
      // Se o batch falhar, tentar sync individual como fallback
      print('🔄 [OfflineSync] Fallback para sync individual...');
      return await _syncAllIndividual();
    }

    // 7. Sincronizar Outbox (fila de envio) - após todos os syncs
    try {
      final outboxSuccess = await trySyncNow();
      results.outbox = SyncResult(
        success: outboxSuccess,
        message: outboxSuccess ? 'Outbox sincronizado' : 'Falha no outbox',
        count: 0,
      );
      print('${outboxSuccess ? "✅" : "❌"} [Outbox] ${results.outbox.message}');
    } catch (e) {
      print('❌ [Outbox] Erro: $e');
      results.outbox = SyncResult(success: false, message: e.toString(), count: 0);
    }

    // Resumo final
    print('\n📊 [OfflineSync] RESUMO DA SINCRONIZAÇÃO:');
    print('   👥 Usuários: ${results.users.count} (${results.users.success ? "OK" : "FALHA"})');
    print('   🎓 Alunos: ${results.alunos.count} (${results.alunos.success ? "OK" : "FALHA"})');
    print('   👤 Pessoas: ${results.pessoas.count} (${results.pessoas.success ? "OK" : "FALHA"})');
    print('   📝 Logs: ${results.logs.count} (${results.logs.success ? "OK" : "FALHA"})');
    print('   🏨 Quartos: ${results.quartos.count} (${results.quartos.success ? "OK" : "FALHA"})');
    print('   📢 Eventos: ${results.eventos.count} (${results.eventos.success ? "OK" : "FALHA"})');
    print('   📤 Outbox: ${results.outbox.success ? "OK" : "FALHA"}');

    _isSyncing = false; // Liberar lock
    return results;
  }

  // -----------------------------
  // Sync Eventos (notificações de ações críticas)
  // -----------------------------
  Future<SyncResult> _syncEventos() async {
    try {
      print('🔄 [EventosSync] Iniciando sincronização de eventos...');

      // Buscar último timestamp processado
      final prefs = await SharedPreferences.getInstance();
      final ultimoTimestamp = prefs.getString('ultimo_evento_timestamp');

      final client = http.Client();
      final body = {
        'action': 'getEventos',
        if (ultimoTimestamp != null) 'timestamp': ultimoTimestamp,
      };

      final request = http.Request('POST', Uri.parse(_sheetsWebhook))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json; charset=utf-8'
        ..headers['Accept'] = 'application/json'
        ..headers['User-Agent'] = 'Flutter-App/1.0'
        ..body = jsonEncode(body);

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      client.close();

      print('📡 [EventosSync] Status: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('❌ [EventosSync] Erro HTTP ${response.statusCode}');
        return SyncResult(
          success: false,
          count: 0,
          message: 'Erro HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      if (data['success'] != true) {
        final msg = data['message'] ?? 'Erro desconhecido';
        print('⚠️ [EventosSync] $msg');
        return SyncResult(success: true, count: 0, message: msg);
      }

      final eventosData = data['eventos'] ?? [];
      print('📊 [EventosSync] Total de eventos recebidos: ${eventosData.length}');

      if (eventosData.isEmpty) {
        print('✅ [EventosSync] Nenhum evento pendente');
        return SyncResult(success: true, count: 0, message: 'Nenhum evento pendente');
      }

      int processados = 0;
      String? novoTimestamp;

      for (final eventoJson in eventosData) {
        try {
          final evento = Evento.fromJson(eventoJson);
          print('📢 [EventosSync] Processando evento: ${evento.tipoEvento} (${evento.id})');

          // Processar o evento
          await _processarEvento(evento);

          // Marcar como processado no servidor
          await _marcarEventoProcessado(evento.id);

          processados++;

          // Atualizar timestamp
          novoTimestamp = evento.timestamp.toIso8601String();
        } catch (e) {
          print('❌ [EventosSync] Erro ao processar evento: $e');
        }
      }

      // Salvar último timestamp processado
      if (novoTimestamp != null) {
        await prefs.setString('ultimo_evento_timestamp', novoTimestamp);
      }

      print('✅ [EventosSync] $processados evento(s) processado(s)');
      return SyncResult(
        success: true,
        count: processados,
        message: '$processados evento(s) processado(s)',
      );
    } catch (e, stack) {
      print('❌ [EventosSync] Erro geral: $e');
      await Sentry.captureException(e, stackTrace: stack);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  /// Processa um evento específico
  Future<void> _processarEvento(Evento evento) async {
    print('🔍 [ProcessarEvento] Tipo: ${evento.tipoEvento}');

    switch (evento.tipoEvento) {
      case 'VIAGEM_ENCERRADA':
        await _processarEventoViagemEncerrada(evento);
        break;
      default:
        print('⚠️ [ProcessarEvento] Tipo desconhecido: ${evento.tipoEvento}');
    }
  }

  /// Processa evento de viagem encerrada
  Future<void> _processarEventoViagemEncerrada(Evento evento) async {
    print('🧹 [ViagemEncerrada] Limpando dados locais...');

    final tipo = evento.dados['tipo'];
    final inicioViagem = evento.inicioViagem;
    final fimViagem = evento.fimViagem;

    if (tipo == 'TODAS') {
      // Limpar TUDO
      print('🧹 [ViagemEncerrada] Limpando TODAS as viagens');
      await _db.limparTodosDados();
    } else if (tipo == 'ESPECIFICA' && inicioViagem != null && fimViagem != null) {
      // Limpar viagem específica
      print('🧹 [ViagemEncerrada] Limpando viagem: $inicioViagem a $fimViagem');
      await _db.limparDadosPorViagem(inicioViagem, fimViagem);
    }

    print('✅ [ViagemEncerrada] Dados locais limpos com sucesso');
  }

  /// Marca evento como processado no servidor
  Future<void> _marcarEventoProcessado(String eventoId) async {
    try {
      final body = {
        'action': 'marcarEventoProcessado',
        'evento_id': eventoId,
      };

      final response = await http.post(
        Uri.parse(_sheetsWebhook),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ [EventosSync] Evento $eventoId marcado como processado');
        } else {
          print('⚠️ [EventosSync] Falha ao marcar evento: ${data['message']}');
        }
      }
    } catch (e) {
      print('❌ [EventosSync] Erro ao marcar evento processado: $e');
      // Não propagar erro - não é crítico
    }
  }

  // ========================================================================
  // MÉTODOS AUXILIARES PARA BATCHING E DELTA SYNC
  // ========================================================================

  /// Processa resposta de users do batch
  Future<SyncResult> _processUsersResponse(Map<String, dynamic> data) async {
    try {
      if (data['users'] is List) {
        final usuarios = (data['users'] as List);
        print('📥 [BatchSync] Processando ${usuarios.length} usuários');

        await _db.deleteAllUsuarios();

        for (final u in usuarios) {
          if (u is! Map) continue;
          final usuario = Map<String, dynamic>.from(u);
          final senhaOriginal = (usuario['senha'] ?? '').toString();
          final senhaHash = _hashSenha(senhaOriginal);

          await _db.upsertUsuario({
            'user_id': (usuario['id'] ?? '').toString(),
            'nome': usuario['nome'],
            'cpf': (usuario['cpf'] ?? '').toString().trim(),
            'senha_hash': senhaHash,
            'perfil': (usuario['perfil'] ?? 'USUARIO').toString().toUpperCase(),
            'ativo': 1,
          });
        }

        final total = await _db.getTotalUsuarios();
        print('✅ [BatchSync] $total usuários sincronizados');
        return SyncResult(success: true, message: '$total usuários', count: total);
      }

      return SyncResult(success: false, message: 'Dados inválidos', count: 0);
    } catch (e) {
      print('❌ [BatchSync] Erro ao processar users: $e');
      return SyncResult(success: false, message: e.toString(), count: 0);
    }
  }

  /// Processa resposta de pessoas do batch
  Future<SyncResult> _processPessoasResponse(Map<String, dynamic> data) async {
    try {
      if (data['data'] is List) {
        final pessoas = (data['data'] as List);
        print('📥 [BatchSync] Processando ${pessoas.length} pessoas');

        int count = 0;
        for (final p in pessoas) {
          if (p is! Map) continue;
          final pessoa = Map<String, dynamic>.from(p);

          final embedding = pessoa['embedding'];
          List<double>? embeddingList;
          if (embedding != null) {
            if (embedding is String) {
              final parsed = jsonDecode(embedding);
              if (parsed is List) {
                embeddingList = parsed.map((e) => (e as num).toDouble()).toList();
              }
            } else if (embedding is List) {
              embeddingList = embedding.map((e) => (e as num).toDouble()).toList();
            }
          }

          await _db.upsertPessoaFacial({
            'cpf': (pessoa['cpf'] ?? '').toString().trim(),
            'nome': pessoa['nome'],
            'colegio': pessoa['colegio'] ?? '',
            'turma': pessoa['turma'] ?? '',
            'email': pessoa['email'] ?? '',
            'telefone': pessoa['telefone'] ?? '',
            'embedding': embeddingList != null ? jsonEncode(embeddingList) : null,
            'facial_status': 'CADASTRADA',
            'movimentacao': pessoa['movimentacao'] ?? '',
            'inicio_viagem': pessoa['inicio_viagem'] ?? '',
            'fim_viagem': pessoa['fim_viagem'] ?? '',
          });
          count++;
        }

        print('✅ [BatchSync] $count pessoas sincronizadas');
        return SyncResult(success: true, message: '$count pessoas', count: count);
      }

      return SyncResult(success: false, message: 'Dados inválidos', count: 0);
    } catch (e) {
      print('❌ [BatchSync] Erro ao processar pessoas: $e');
      return SyncResult(success: false, message: e.toString(), count: 0);
    }
  }

  /// Processa resposta de alunos do batch
  Future<SyncResult> _processAlunosResponse(Map<String, dynamic> data) async {
    try {
      if (data['data'] is List) {
        final alunos = (data['data'] as List);
        print('📥 [BatchSync] Processando ${alunos.length} alunos');

        int count = 0;
        for (final a in alunos) {
          if (a is! Map) continue;
          final aluno = Map<String, dynamic>.from(a);

          await _db.upsertAluno({
            'cpf': (aluno['cpf'] ?? '').toString().trim(),
            'nome': aluno['nome'],
            'colegio': aluno['colegio'] ?? '',
            'turma': aluno['turma'] ?? '',
            'email': aluno['email'] ?? '',
            'telefone': aluno['telefone'] ?? '',
            'facial': aluno['facial_status'] ?? 'NAO',
            'tem_qr': aluno['tem_qr'] ?? 'NAO',
            'inicio_viagem': aluno['inicio_viagem'] ?? '',
            'fim_viagem': aluno['fim_viagem'] ?? '',
          });
          count++;
        }

        print('✅ [BatchSync] $count alunos sincronizados');
        return SyncResult(success: true, message: '$count alunos', count: count);
      }

      return SyncResult(success: false, message: 'Dados inválidos', count: 0);
    } catch (e) {
      print('❌ [BatchSync] Erro ao processar alunos: $e');
      return SyncResult(success: false, message: e.toString(), count: 0);
    }
  }

  /// Processa resposta de logs do batch
  Future<SyncResult> _processLogsResponse(Map<String, dynamic> data) async {
    try {
      if (data['data'] is List) {
        final logs = (data['data'] as List);
        print('📥 [BatchSync] Processando ${logs.length} logs');

        int count = 0;
        for (final l in logs) {
          if (l is! Map) continue;
          final log = Map<String, dynamic>.from(l);

          await _db.insertLog(
            cpf: (log['cpf'] ?? '').toString(),
            personName: log['nome'] ?? '',
            timestamp: DateTime.parse(log['timestamp']),
            confidence: (log['confidence'] ?? 0.0) as double,
            tipo: log['tipo'] ?? 'RECONHECIMENTO',
            operadorNome: log['operador'] ?? '',
            colegio: log['colegio'] ?? '',
            turma: log['turma'] ?? '',
            inicioViagem: log['inicio_viagem'] ?? '',
            fimViagem: log['fim_viagem'] ?? '',
          );
          count++;
        }

        print('✅ [BatchSync] $count logs sincronizados');
        return SyncResult(success: true, message: '$count logs', count: count);
      }

      return SyncResult(success: false, message: 'Dados inválidos', count: 0);
    } catch (e) {
      print('❌ [BatchSync] Erro ao processar logs: $e');
      return SyncResult(success: false, message: e.toString(), count: 0);
    }
  }

  /// Processa resposta de quartos do batch
  Future<SyncResult> _processQuartosResponse(Map<String, dynamic> data) async {
    try {
      if (data['data'] is List) {
        final quartos = (data['data'] as List);
        print('📥 [BatchSync] Processando ${quartos.length} quartos');

        await _db.limparQuartos();
        int count = 0;

        for (final q in quartos) {
          if (q is! Map) continue;
          final quarto = Map<String, dynamic>.from(q);

          await _db.insertQuarto({
            'numero_quarto': quarto['Quarto'] ?? '',
            'escola': quarto['Escola'] ?? '',
            'nome_hospede': quarto['Nome do Hóspede'] ?? '',
            'cpf': quarto['CPF'] ?? '',
            'inicio_viagem': quarto['Início Viagem'] ?? '',
            'fim_viagem': quarto['Fim Viagem'] ?? '',
          });
          count++;
        }

        print('✅ [BatchSync] $count quartos sincronizados');
        return SyncResult(success: true, message: '$count quartos', count: count);
      }

      return SyncResult(success: false, message: 'Dados inválidos', count: 0);
    } catch (e) {
      print('❌ [BatchSync] Erro ao processar quartos: $e');
      return SyncResult(success: false, message: e.toString(), count: 0);
    }
  }

  /// Processa resposta de eventos do batch
  Future<SyncResult> _processEventosResponse(Map<String, dynamic> data) async {
    try {
      if (data['eventos'] is List) {
        final eventos = (data['eventos'] as List);
        print('📥 [BatchSync] Processando ${eventos.length} eventos');

        for (final e in eventos) {
          if (e is! Map) continue;
          final evento = Evento.fromJson(Map<String, dynamic>.from(e));
          await _processarEvento(evento);
          await _marcarEventoProcessado(evento.id);
        }

        print('✅ [BatchSync] ${eventos.length} eventos processados');
        return SyncResult(success: true, message: '${eventos.length} eventos', count: eventos.length);
      }

      return SyncResult(success: true, message: 'Nenhum evento pendente', count: 0);
    } catch (e) {
      print('❌ [BatchSync] Erro ao processar eventos: $e');
      return SyncResult(success: false, message: e.toString(), count: 0);
    }
  }

  /// Fallback: Sync individual quando batch falhar
  Future<ConsolidatedSyncResult> _syncAllIndividual() async {
    print('🔄 [OfflineSync] Executando sync individual (fallback)...');

    final results = ConsolidatedSyncResult();

    // Executar syncs em paralelo (código antigo)
    await Future.wait([
      _syncUsers().then((userResult) {
        results.users = userResult;
      }).catchError((e) {
        results.users = SyncResult(success: false, message: e.toString(), count: 0);
      }),

      _syncPessoas().then((pessoasResult) {
        results.pessoas = pessoasResult;
        if (pessoasResult.success) {
          FaceRecognitionService.instance.invalidateCache();
        }
      }).catchError((e) {
        results.pessoas = SyncResult(success: false, message: e.toString(), count: 0);
      }),

      _syncAlunos().then((alunosResult) {
        results.alunos = alunosResult;
      }).catchError((e) {
        results.alunos = SyncResult(success: false, message: e.toString(), count: 0);
      }),

      _syncLogs().then((logsResult) {
        results.logs = logsResult;
      }).catchError((e) {
        results.logs = SyncResult(success: false, message: e.toString(), count: 0);
      }),

      _syncQuartos().then((quartosResult) {
        results.quartos = quartosResult;
      }).catchError((e) {
        results.quartos = SyncResult(success: false, message: e.toString(), count: 0);
      }),

      _syncEventos().then((eventosResult) {
        results.eventos = eventosResult;
      }).catchError((e) {
        results.eventos = SyncResult(success: false, message: e.toString(), count: 0);
      }),
    ]);

    return results;
  }

  // -----------------------------
  // Sync Users (do Google Sheets)
  // -----------------------------
  Future<SyncResult> _syncUsers() async {
    print('🔄 [UserSync] Iniciando sincronização de usuários...');
    final uri = Uri.parse('$_sheetsWebhook?action=getAllUsers');

    http.Response resp;
    try {
      resp = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      print('❌ [UserSync] Falha de conexão: $e');
      return SyncResult(success: false, message: 'Falha de conexão', count: 0);
    }

    print('📥 [UserSync] Status: ${resp.statusCode}');

    if (resp.statusCode != 200) {
      print('📥 [UserSync] Body (não-200): ${resp.body}');
      return SyncResult(success: false, message: 'Erro HTTP: ${resp.statusCode}', count: 0);
    }

    dynamic data;
    try {
      data = jsonDecode(resp.body);
    } catch (e) {
      print('❌ [UserSync] JSON inválido: $e');
      return SyncResult(success: false, message: 'JSON inválido', count: 0);
    }

    if (data is Map && data['success'] == true && data['users'] is List) {
      final usuarios = (data['users'] as List);

      print('📥 [UserSync] Recebidos ${usuarios.length} usuários');
      await _db.deleteAllUsuarios();

      for (final u in usuarios) {
        if (u is! Map) continue;
        final usuario = Map<String, dynamic>.from(u);
        final senhaOriginal = (usuario['senha'] ?? '').toString();
        final senhaHash = _hashSenha(senhaOriginal);

        await _db.upsertUsuario({
          'user_id': (usuario['id'] ?? '').toString(),
          'nome': usuario['nome'],
          'cpf': (usuario['cpf'] ?? '').toString().trim(),
          'senha_hash': senhaHash,
          'perfil': (usuario['perfil'] ?? 'USUARIO').toString().toUpperCase(),
          'ativo': 1,
        });
      }

      final total = await _db.getTotalUsuarios();
      print('✅ [UserSync] $total usuários sincronizados');
      return SyncResult(success: true, message: '$total usuários sincronizados', count: total);
    }

    print('⚠️ [UserSync] Resposta sem usuários');
    return SyncResult(success: false, message: 'Nenhum usuário encontrado', count: 0);
  }

  // -----------------------------
  // Sync Alunos (aba Alunos)
  // -----------------------------
  Future<SyncResult> _syncAlunos() async {
    try {
      await Sentry.captureMessage(
        'Iniciando sincronização de alunos',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('sync_type', 'alunos');
          scope.setTag('source', 'google_sheets');
        },
      );

      print('🔄 [AlunosSync] Iniciando sincronização de alunos...');

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(_sheetsWebhook))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json; charset=utf-8'
        ..headers['Accept'] = 'application/json'
        ..headers['X-Requested-With'] = 'XMLHttpRequest'
        ..headers['User-Agent'] = 'PostmanRuntime/7.32.3'
        ..body = jsonEncode({'action': 'getAllStudents'});

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      client.close();

      print('📡 [AlunosSync] Status: ${response.statusCode}');

      if (response.statusCode == 302 && response.headers['location'] != null) {
        final redirectedUrl = response.headers['location']!;
        print('🔁 [AlunosSync] Redirecionando para: $redirectedUrl');

        http.Response redirectedResponse = await _followRedirect(
          redirectedUrl,
          {'action': 'getAllStudents'},
        );

        return await _processarRespostaAlunos(redirectedResponse);
      }

      if (response.statusCode == 200) {
        return await _processarRespostaAlunos(response);
      }

      return SyncResult(
        success: false,
        count: 0,
        message: 'Erro HTTP ${response.statusCode}',
      );
    } catch (e, stack) {
      print('❌ [AlunosSync] Erro geral: $e');
      await Sentry.captureException(e, stackTrace: stack);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  // -----------------------------
  // Sync Pessoas (com embeddings)
  // -----------------------------
  Future<SyncResult> _syncPessoas() async {
    try {
      await Sentry.captureMessage(
        'Iniciando sincronização de pessoas com embeddings',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('sync_type', 'pessoas');
          scope.setTag('source', 'google_sheets');
        },
      );

      print('🔄 [PessoasSync] Iniciando sincronização de PESSOAS (com embeddings)...');

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(_sheetsWebhook))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json; charset=utf-8'
        ..headers['Accept'] = 'application/json'
        ..headers['X-Requested-With'] = 'XMLHttpRequest'
        ..headers['User-Agent'] = 'PostmanRuntime/7.32.3'
        ..body = jsonEncode({'action': 'getAllPeople'});

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      client.close();

      print('📡 [PessoasSync] Status: ${response.statusCode}');

      if (response.statusCode == 302 && response.headers['location'] != null) {
        final redirectedUrl = response.headers['location']!;
        print('🔁 [PessoasSync] Redirecionando para: $redirectedUrl');

        http.Response redirectedResponse = await _followRedirect(
          redirectedUrl,
          {'action': 'getAllPeople'},
        );

        return await _processarRespostaPessoas(redirectedResponse);
      }

      if (response.statusCode == 200) {
        return await _processarRespostaPessoas(response);
      }

      return SyncResult(
        success: false,
        count: 0,
        message: 'Erro HTTP ${response.statusCode}',
      );
    } catch (e, stack) {
      print('❌ [PessoasSync] Erro geral: $e');
      await Sentry.captureException(e, stackTrace: stack);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  // -----------------------------
  // Sync Logs (aba LOGS)
  // -----------------------------
  Future<SyncResult> _syncLogs() async {
    try {
      print('🔄 [LogsSync] Iniciando sincronização de logs...');

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(_sheetsWebhook))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json; charset=utf-8'
        ..headers['Accept'] = 'application/json'
        ..headers['X-Requested-With'] = 'XMLHttpRequest'
        ..headers['User-Agent'] = 'PostmanRuntime/7.32.3'
        ..body = jsonEncode({'action': 'getAllLogs'});

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      client.close();

      print('📡 [LogsSync] Status: ${response.statusCode}');

      if (response.statusCode == 302 && response.headers['location'] != null) {
        final redirectedUrl = response.headers['location']!;
        print('🔁 [LogsSync] Redirecionando para: $redirectedUrl');

        http.Response redirectedResponse = await _followRedirect(
          redirectedUrl,
          {'action': 'getAllLogs'},
        );

        return await _processarRespostaLogs(redirectedResponse);
      }

      if (response.statusCode == 200) {
        return await _processarRespostaLogs(response);
      }

      return SyncResult(
        success: false,
        count: 0,
        message: 'Erro HTTP ${response.statusCode}',
      );
    } catch (e, stack) {
      print('❌ [LogsSync] Erro geral: $e');
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  // -----------------------------
  // Sync Quartos (aba HOMELIST)
  // -----------------------------
  Future<SyncResult> _syncQuartos() async {
    try {
      print('🔄 [QuartosSync] Delegando para QuartosSyncService...');

      // Importar QuartosSyncService dinamicamente para evitar dependência circular
      final quartosSyncService = QuartosSyncService.instance;
      final result = await quartosSyncService.syncQuartosFromSheets();

      print('${result.success ? "✅" : "❌"} [QuartosSync] ${result.message}');
      return result;
    } catch (e, stack) {
      print('❌ [QuartosSync] Erro geral: $e');
      await Sentry.captureException(e, stackTrace: stack);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  // -----------------------------
  // Helper: Follow Redirect
  // -----------------------------
  Future<http.Response> _followRedirect(String redirectedUrl, Map<String, dynamic> body) async {
    try {
      http.Response redirectedResponse = await http.post(
        Uri.parse(redirectedUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'User-Agent': 'PostmanRuntime/7.32.3',
        },
        body: jsonEncode(body),
      );

      // Se POST não funcionar (405), tentar GET
      if (redirectedResponse.statusCode == 405) {
        print('⚠️ [Redirected] POST não permitido, tentando GET...');
        redirectedResponse = await http.get(
          Uri.parse(redirectedUrl),
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'PostmanRuntime/7.32.3',
            'X-Requested-With': 'XMLHttpRequest',
          },
        );
      }

      return redirectedResponse;
    } catch (e) {
      print('❌ [Redirected] Erro ao seguir redirect: $e');
      await Sentry.captureException(
        e,
        hint: Hint.withMap({
          'context': 'Erro ao seguir redirect',
          'redirected_url': redirectedUrl,
        }),
      );
      rethrow;
    }
  }

  // -----------------------------
  // Processors
  // -----------------------------
  Future<SyncResult> _processarRespostaAlunos(http.Response response) async {
    try {
      final data = jsonDecode(response.body);

      if (data['success'] != true) {
        final msg = data['message'] ?? 'Erro desconhecido';
        print('❌ [AlunosSync] Erro: $msg');
        return SyncResult(success: false, count: 0, message: msg);
      }

      final alunos = data['data'] ?? [];
      print('📊 [AlunosSync] Total de alunos recebidos: ${alunos.length}');
      int count = 0;

      for (final aluno in alunos) {
        try {
          final alunoData = {
            'cpf': aluno['cpf'] ?? '',
            'nome': aluno['nome'] ?? '',
            'colegio': aluno['colegio'] ?? '',
            'turma': aluno['turma'] ?? '',
            'email': aluno['email'] ?? '',
            'telefone': aluno['telefone'] ?? '',
            'facial': aluno['facial_status'],
            'tem_qr': aluno['tem_qr'] ?? aluno['pulseira'] ?? 'NAO',
            'inicio_viagem': aluno['inicio_viagem'] ?? '',
            'fim_viagem': aluno['fim_viagem'] ?? '',
          };
          await _db.upsertAluno(alunoData);
          count++;
        } catch (e) {
          print('❌ Erro ao salvar aluno ${aluno['nome']}: $e');
        }
      }

      print('✅ [$count] alunos sincronizados com sucesso');

      await Sentry.captureMessage(
        'Sincronização de alunos concluída',
        level: SentryLevel.info,
      );

      return SyncResult(success: true, count: count, message: 'Alunos sincronizados');
    } catch (e) {
      print('❌ [ProcessarRespostaAlunos] Erro: $e');
      await Sentry.captureException(e);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  Future<SyncResult> _processarRespostaPessoas(http.Response response) async {
    try {
      final data = jsonDecode(response.body);

      if (data['success'] != true) {
        final msg = data['message'] ?? 'Erro desconhecido';
        print('❌ [PessoasSync] Erro: $msg');
        return SyncResult(success: false, count: 0, message: msg);
      }

      final pessoas = data['data'] ?? [];
      print('📊 [PessoasSync] Total de pessoas recebidas: ${pessoas.length}');
      int countPessoas = 0;
      int countEmbeddings = 0;

      for (final pessoa in pessoas) {
        try {
          if (pessoa['embedding'] != null && pessoa['embedding'] != '') {
            try {
              List<double> embedding;

              if (pessoa['embedding'] is String) {
                final embeddingStr = pessoa['embedding'] as String;
                if (embeddingStr.isEmpty || embeddingStr.contains('T') || embeddingStr.length < 10) {
                  print('⚠️ [${pessoa['cpf']}] Embedding inválido');
                  continue;
                }

                final embeddingList = jsonDecode(embeddingStr);
                if (embeddingList is! List) {
                  print('⚠️ [${pessoa['cpf']}] Embedding não é um array');
                  continue;
                }
                embedding = List<double>.from(embeddingList);
              } else if (pessoa['embedding'] is List) {
                embedding = List<double>.from(pessoa['embedding']);
              } else {
                print('⚠️ [${pessoa['cpf']}] Tipo de embedding não suportado');
                continue;
              }

              if (embedding.isEmpty || embedding.length < 50) {
                print('⚠️ [${pessoa['cpf']}] Embedding com tamanho suspeito: ${embedding.length}');
                continue;
              }

              // 🔍 DIAGNÓSTICO: Ver movimentação recebida do Sheets
              final movimentacaoRecebida = pessoa['movimentacao'] ?? '';
              final movimentacaoFinal = movimentacaoRecebida.toString().toUpperCase();
              print('🔍 [${pessoa['nome']}] Movimentação recebida: "$movimentacaoRecebida" → Final: "$movimentacaoFinal"');

              await _db.upsertPessoaFacial({
                'cpf': pessoa['cpf'] ?? '',
                'nome': pessoa['nome'] ?? '',
                'colegio': pessoa['colegio'] ?? '',
                'turma': pessoa['turma'] ?? '',
                'email': pessoa['email'] ?? '',
                'telefone': pessoa['telefone'] ?? '',
                'embedding': jsonEncode(embedding),
                'facial_status': 'CADASTRADA',
                'movimentacao': movimentacaoFinal,
                'inicio_viagem': pessoa['inicio_viagem'] ?? '',
                'fim_viagem': pessoa['fim_viagem'] ?? '',
              });

              countPessoas++;
              countEmbeddings++;
              print('✅ [${pessoa['cpf']}] Pessoa e embedding salvos (${embedding.length} dims)');
            } catch (e, stack) {
              print('❌ [${pessoa['cpf']}] Erro ao processar: $e');
            }
          } else {
            print('⚠️ [${pessoa['cpf']}] Pessoa sem embedding');
          }
        } catch (e) {
          print('❌ Erro ao salvar pessoa ${pessoa['cpf']}: $e');
        }
      }

      print('✅ [$countPessoas] pessoas e [$countEmbeddings] embeddings sincronizados');

      await Sentry.captureMessage(
        'Sincronização de pessoas concluída',
        level: SentryLevel.info,
      );

      return SyncResult(
        success: true,
        count: countPessoas,
        message: '$countPessoas pessoas e $countEmbeddings embeddings sincronizados'
      );
    } catch (e) {
      print('❌ [ProcessarRespostaPessoas] Erro: $e');
      await Sentry.captureException(e);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  Future<SyncResult> _processarRespostaLogs(http.Response response) async {
    try {
      final data = jsonDecode(response.body);

      if (data['success'] != true) {
        final msg = data['message'] ?? 'Erro desconhecido';
        print('❌ [LogsSync] Erro: $msg');
        return SyncResult(success: false, count: 0, message: msg);
      }

      final logs = data['data'] ?? [];
      print('📊 [LogsSync] Total de logs recebidos: ${logs.length}');
      int count = 0;

      for (final log in logs) {
        try {
          DateTime timestamp;
          try {
            if (log['timestamp'] is String) {
              timestamp = DateTime.parse(log['timestamp']);
            } else if (log['timestamp'] is DateTime) {
              timestamp = log['timestamp'];
            } else {
              timestamp = DateTime.now();
            }
          } catch (e) {
            timestamp = DateTime.now();
          }

          final personName = log['person_name'] ?? log['nome'] ?? '';
          final cpf = (log['cpf'] ?? log['person_id'] ?? '').toString();

          await _db.insertLog(
            cpf: cpf,
            personName: personName,
            timestamp: timestamp,
            confidence: (log['confidence'] ?? 0.0).toDouble(),
            tipo: log['tipo'] ?? 'FACIAL',
            operadorNome: log['operador_nome'] ?? log['operador'] ?? '',
            colegio: log['colegio'] ?? '',
            turma: log['turma'] ?? '',
            inicioViagem: log['inicio_viagem'] ?? '',
            fimViagem: log['fim_viagem'] ?? '',
            updateMovimentacao: false, // ✅ NÃO atualizar movimentacao com logs históricos
          );
          count++;
        } catch (e) {
          if (!e.toString().contains('UNIQUE constraint failed')) {
            print('❌ Erro ao salvar log: $e');
          }
        }
      }

      print('✅ [$count] logs sincronizados com sucesso');
      return SyncResult(success: true, count: count, message: '$count logs sincronizados');
    } catch (e) {
      print('❌ [ProcessarRespostaLogs] Erro: $e');
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  // -----------------------------
  // Utilities
  // -----------------------------
  String _hashSenha(String senha) => sha256.convert(utf8.encode(senha)).toString();

  bool verificarSenha(String senha, String senhaHash) => _hashSenha(senha) == senhaHash;

  Future<bool> temUsuariosLocais() async => (await _db.getTotalUsuarios()) > 0;

  Future<bool> temAlunosLocais() async {
    try {
      final alunos = await _db.getAllAlunos();
      return alunos.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<bool> temLogsLocais() async {
    try {
      final logs = await _db.getAllLogs();
      return logs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}

class _BatchResult {
  final bool allSucceeded;
  final List<Map<String, dynamic>> notConfirmedItems;
  const _BatchResult({required this.allSucceeded, required this.notConfirmedItems});
}

// ====================================================================
// CLASSES DE RESULTADO PARA SINCRONIZAÇÃO
// ====================================================================

/// Resultado de sincronização individual (Users, Alunos, Logs, etc)
class SyncResult {
  final bool success;
  final String message;
  final int count;

  SyncResult({
    required this.success,
    required this.message,
    required this.count,
  });

  @override
  String toString() => 'SyncResult(success: $success, count: $count, message: $message)';
}

/// Resultado consolidado de sincronização completa
class ConsolidatedSyncResult {
  bool hasInternet = true;
  SyncResult users = SyncResult(success: false, message: 'Não sincronizado', count: 0);
  SyncResult alunos = SyncResult(success: false, message: 'Não sincronizado', count: 0);
  SyncResult pessoas = SyncResult(success: false, message: 'Não sincronizado', count: 0);
  SyncResult logs = SyncResult(success: false, message: 'Não sincronizado', count: 0);
  SyncResult quartos = SyncResult(success: false, message: 'Não sincronizado', count: 0);
  SyncResult eventos = SyncResult(success: false, message: 'Não sincronizado', count: 0);
  SyncResult outbox = SyncResult(success: false, message: 'Não sincronizado', count: 0);

  /// Retorna true se TODAS as sincronizações foram bem-sucedidas
  bool get allSuccess =>
      hasInternet &&
      users.success &&
      alunos.success &&
      pessoas.success &&
      logs.success &&
      quartos.success &&
      eventos.success &&
      outbox.success;

  /// Retorna true se ALGUMA sincronização foi bem-sucedida
  bool get anySuccess =>
      users.success ||
      alunos.success ||
      pessoas.success ||
      logs.success ||
      quartos.success ||
      eventos.success ||
      outbox.success;

  /// Total de itens sincronizados
  int get totalCount =>
      users.count +
      alunos.count +
      pessoas.count +
      logs.count +
      quartos.count +
      eventos.count;

  @override
  String toString() {
    return '''
ConsolidatedSyncResult(
  hasInternet: $hasInternet,
  allSuccess: $allSuccess,
  anySuccess: $anySuccess,
  totalCount: $totalCount,
  users: ${users.count} (${users.success ? "OK" : "FALHA"}),
  alunos: ${alunos.count} (${alunos.success ? "OK" : "FALHA"}),
  pessoas: ${pessoas.count} (${pessoas.success ? "OK" : "FALHA"}),
  logs: ${logs.count} (${logs.success ? "OK" : "FALHA"}),
  quartos: ${quartos.count} (${quartos.success ? "OK" : "FALHA"}),
  eventos: ${eventos.count} (${eventos.success ? "OK" : "FALHA"}),
  outbox: ${outbox.success ? "OK" : "FALHA"}
)''';
  }
}
