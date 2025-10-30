// lib/services/offline_sync_service.dart — VERSÃO CORRIGIDA (envio inteligente + sync embeddings)
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:embarqueellus/database/database_helper.dart';

/// Serviço de sincronização offline com Google Apps Script / Google Sheets.
///
/// Estratégia:
/// - Movimentações: tenta LOTE; se parcial/falha, fallback por item (retries).
/// - Cadastros faciais: envia sempre individualmente (compatível com seu GAS).
/// - Remove da fila apenas itens confirmados.
/// - Trata 301/302 do GAS como sucesso (POST processado).
/// - Sincroniza embeddings do servidor para o SQLite no init().
class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  final String _sheetsWebhook = 'https://script.google.com/macros/s/AKfycbz8H_y2g5Zh8KvzxZiFKS4ToQjhfXZ2rlFjOHBAjCZXAksT96jevRekqYjAsVarETcI/exec';
  final DatabaseHelper _db = DatabaseHelper.instance;

  Timer? _syncTimer;

  /// Inicializa o agendador de sincronização automática (1 min) + sync de embeddings.
  void init() {
    _syncTimer?.cancel();

    _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      print('⏰ [OfflineSync] Timer de sincronização disparado');
      await trySyncNow();
    });

    print('✅ [OfflineSync] Sincronização automática iniciada (a cada 1 minuto)');
    trySyncNow();
    // 🔽 Faz o download dos embeddings no startup (após limpar dados, garante reconhecimento)
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
  }) async {
    await _db.insertLog(
      cpf: cpf,
      personName: personName,
      timestamp: timestamp,
      confidence: confidence,
      tipo: tipo,
    );

    await _db.enqueueOutbox('movement_log', {
      'cpf': cpf,
      'personName': personName,
      'timestamp': timestamp.toIso8601String(),
      'confidence': confidence,
      'personId': personId,
      'tipo': tipo,
    });

    print('📝 [OfflineSync] Log enfileirado: $personName - $tipo');
  }

  Future<void> queueCadastroFacial({
    required String cpf,
    required String nome,
    required String email,
    required String telefone,
    required List<double> embedding,
    required String personId,
  }) async {
    await _db.enqueueOutbox('face_register', {
      'cpf': cpf,
      'nome': nome,
      'email': email,
      'telefone': telefone,
      'embedding': embedding,
      'personId': personId,
    });

    print('📝 [OfflineSync] Cadastro facial enfileirado: $nome');
  }

  // -----------------------------
  // Execução de sync
  // -----------------------------

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
      // 1) cadastros faciais — individual
      if (faceRegisters.isNotEmpty) {
        print('📸 [OfflineSync] Enviando ${faceRegisters.length} cadastro(s) facial(is) individualmente...');
        for (final item in faceRegisters) {
          final ok = await _sendPersonIndividually(item);
          if (ok) {
            final id = (item['idOutbox'] as int?) ?? -1;
            if (id != -1) successIds.add(id);
          }
        }
      }

      // 2) movimentações — lote + fallback
      if (movementLogs.isNotEmpty) {
        print('📍 [OfflineSync] Tentando envio em LOTE de ${movementLogs.length} movimentação(ões)...');
        final lot = await _sendMovementsBatch(movementLogs);

        if (lot.allSucceeded) {
          successIds.addAll(
            movementLogs.map((m) => (m['idOutbox'] as int?) ?? -1).where((id) => id != -1),
          );
          print('✅ [OfflineSync] Lote de movimentações confirmado');
        } else {
          print('⚠️ [OfflineSync] Lote parcial/sem confirmação — fallback individual...');
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

    if (resp.statusCode == 301 || resp.statusCode == 302) {
      return _BatchResult(allSucceeded: true, notConfirmedItems: const []);
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      try {
        final json = jsonDecode(resp.body);
        final success = json is Map && json['success'] == true;
        if (!success) {
          print('⚠️ [OfflineSync] Lote 2xx porém success=false: ${resp.body}');
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
        print('ℹ️ [OfflineSync] Lote 2xx sem JSON — considerando sucesso');
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
    final body = <String, dynamic>{'action': 'cadastrarFacial', ...copy};
    return _postWithRetriesAndSuccess(body);
  }

  // -----------------------------
  // POST helpers (retries & 302)
  // -----------------------------

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

          if (resp.statusCode == 301 || resp.statusCode == 302) return true;

          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            try {
              final json = jsonDecode(resp.body);
              if (json is Map && json['success'] == true) return true;
              print('ℹ️ [OfflineSync] 2xx sem success=true — considerando sucesso.');
              return true;
            } catch (_) {
              print('ℹ️ [OfflineSync] 2xx sem JSON — considerando sucesso.');
              return true;
            }
          }

          print('❌ [OfflineSync] Falha HTTP ${resp.statusCode}: ${resp.body}');
        }
      } catch (e) {
        print('❌ [OfflineSync] Exceção ao enviar: $e (tentativa $attempt/$maxRetries)');
      }
      await Future.delayed(Duration(seconds: attempt)); // backoff simples
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
      return resp;
    } catch (e) {
      print('❌ [OfflineSync] Erro ao enviar POST: $e');
      return null;
    } finally {
      client.close();
    }
  }

  // -----------------------------
  // Download de embeddings do servidor → SQLite
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
      } else if (resp.statusCode == 301 || resp.statusCode == 302) {
        print("ℹ️ [Embeddings] 301/302 recebido — considere sucesso se o GAS já tiver processado.");
      } else {
        print("❌ [Embeddings] HTTP ${resp.statusCode}: ${resp.body}");
      }
    } catch (e) {
      print("❌ [Embeddings] Erro ao buscar embeddings: $e");
    }
  }

  // -----------------------------

  Future<void> testConnection() async {
    print('🔍 [OfflineSync] Testando conexão com Google Apps Script...');
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
