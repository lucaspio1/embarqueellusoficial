// lib/services/offline_sync_service.dart — VERSÃO CORRIGIDA (sem isolate!)
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/config/app_config.dart';

class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  final DatabaseHelper _db = DatabaseHelper.instance;

  // URL lida do arquivo .env
  String get _sheetsWebhook => AppConfig.instance.googleAppsScriptUrl;

  Timer? _syncTimer;

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
  }) async {
    await _db.insertLog(
      cpf: cpf,
      personName: personName,
      timestamp: timestamp,
      confidence: confidence,
      tipo: tipo,
      operadorNome: operadorNome,
    );

    await _db.enqueueOutbox('movement_log', {
      'cpf': cpf,
      'personName': personName,
      'timestamp': timestamp.toIso8601String(),
      'confidence': confidence,
      'personId': personId,
      'tipo': tipo,
      'operadorNome': operadorNome,
    });

    print('📝 [OfflineSync] Log enfileirado: $personName - $tipo (Operador: ${operadorNome ?? "N/A"})');
  }

  Future<void> queueCadastroFacial({
    required String cpf,
    required String nome,
    required String email,
    required String telefone,
    required List<double> embedding,
    required String personId,
    String? inicioViagem,
    String? fimViagem,
  }) async {
    await _db.enqueueOutbox('face_register', {
      'cpf': cpf,
      'nome': nome,
      'email': email,
      'telefone': telefone,
      'embedding': embedding,
      'personId': personId,
      'movimentacao': 'QUARTO', // ✅ JÁ ENVIA COM MOVIMENTAÇÃO INICIAL
      'inicio_viagem': inicioViagem ?? '',
      'fim_viagem': fimViagem ?? '',
    });

    print('📝 [OfflineSync] Cadastro facial enfileirado: $nome (Local inicial: QUARTO, Viagem: ${inicioViagem ?? "N/A"} a ${fimViagem ?? "N/A"})');
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
      await trySyncNow();
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
      'email': copy['email'] ?? '',
      'telefone': copy['telefone'] ?? '',
      'embedding': copy['embedding'],
      'personId': copy['personId'] ?? copy['cpf'],
      'movimentacao': copy['movimentacao'] ?? 'QUARTO', // ✅ GARANTE QUE SEMPRE VAI COM QUARTO
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
}

class _BatchResult {
  final bool allSucceeded;
  final List<Map<String, dynamic>> notConfirmedItems;
  const _BatchResult({required this.allSucceeded, required this.notConfirmedItems});
}
