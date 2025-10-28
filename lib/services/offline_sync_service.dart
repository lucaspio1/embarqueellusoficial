import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '/database/database_helper.dart';

class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  final String _sheetsWebhook = 'https://script.google.com/macros/s/AKfycbyO6m7XXvMvpi5Mm9M_a2rZ5ZCEmBXN2xXqHd9VrUbkozs-eNZfEsAmDJROd65Jn36H/exec';
  final _db = DatabaseHelper.instance;

  Future<void> init() async {
    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        print('🌐 [OfflineSync] Conexão detectada, tentando sincronizar...');
        trySyncNow();
      }
    });
  }

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

    try {
      if (faceRegisters.isNotEmpty) {
        print('📸 [OfflineSync] Enviando ${faceRegisters.length} cadastros faciais...');
        await _sendToSheets('addPerson', faceRegisters);
      }
      if (movementLogs.isNotEmpty) {
        print('📍 [OfflineSync] Enviando ${movementLogs.length} logs de movimentação...');
        await _sendToSheets('addMovementLog', movementLogs);
      }
      await _db.deleteOutboxIds(batch.map<int>((e) => e['id'] as int).toList());
      print('✅ [OfflineSync] Sincronização concluída com sucesso!');
      return true;
    } catch (e) {
      print('❌ [OfflineSync] Erro na sincronização: $e');
      return false;
    }
  }

  /// ✅ MÉTODO CORRIGIDO PARA TRATAR REDIRECIONAMENTO 302
  /// ✅ MÉTODO CORRIGIDO PARA TRATAR REDIRECIONAMENTO 302
  Future<void> _sendToSheets(String action, List<Map<String, dynamic>> items) async {
    print('🌐 [OfflineSync] Enviando $action para Google Sheets...');
    print('🔗 [OfflineSync] URL: $_sheetsWebhook');

    final client = http.Client();

    try {
      final request = http.Request('POST', Uri.parse(_sheetsWebhook))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json; charset=utf-8'
        ..headers['Accept'] = 'application/json'
        ..headers['User-Agent'] = 'Flutter-App/1.0'
        ..body = jsonEncode({'action': action, 'people': items});

      print('📤 [OfflineSync] Enviando requisição...');
      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      print('📡 [OfflineSync] Status recebido: ${response.statusCode}');

      // ✅ TRATAMENTO DE REDIRECIONAMENTO 302 - CORREÇÃO MELHORADA
      if (response.statusCode == 302 || response.statusCode == 301) {
        final redirectUrl = response.headers['location'];

        if (redirectUrl == null || redirectUrl.isEmpty) {
          throw Exception('Redirecionamento sem URL de destino');
        }

        print('🔄 [OfflineSync] Redirecionando para: $redirectUrl');

        // ✅ TENTAR POST PRIMEIRO, SE FALHAR TENTAR GET
        try {
          // Tentativa com POST
          final redirectResponse = await http.post(
            Uri.parse(redirectUrl),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'User-Agent': 'Flutter-App/1.0',
            },
            body: jsonEncode({'action': action, 'people': items}),
          );

          print('📡 [OfflineSync] Status após POST no redirect: ${redirectResponse.statusCode}');

          if (redirectResponse.statusCode >= 200 && redirectResponse.statusCode < 300) {
            return _processResponse(redirectResponse, action, items.length);
          } else if (redirectResponse.statusCode == 405) {
            // ✅ SE 405, TENTAR COM GET E PARÂMETROS NA URL
            print('🔄 [OfflineSync] POST não permitido, tentando GET com parâmetros...');
            await _sendWithGetRedirect(redirectUrl, action, items);
            return;
          } else {
            throw Exception('Erro HTTP ${redirectResponse.statusCode} após redirecionamento');
          }
        } catch (e) {
          print('❌ [OfflineSync] Erro no POST após redirect: $e');
          // Tentar com GET como fallback
          print('🔄 [OfflineSync] Tentando fallback com GET...');
          await _sendWithGetRedirect(redirectUrl, action, items);
          return;
        }
      }

      // ✅ SE NÃO FOR 302, PROCESSAR RESPOSTA NORMALMENTE
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _processResponse(response, action, items.length);
      }

      throw Exception('Erro HTTP ${response.statusCode}');

    } catch (e) {
      print('❌ [OfflineSync] Erro ao enviar para Sheets: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  /// ✅ MÉTODO AUXILIAR PARA ENVIAR VIA GET APÓS REDIRECIONAMENTO
  Future<void> _sendWithGetRedirect(String redirectUrl, String action, List<Map<String, dynamic>> items) async {
    try {
      // Para GET, precisamos codificar os dados na URL
      final encodedData = base64Url.encode(utf8.encode(jsonEncode({
        'action': action,
        'people': items,
      })));

      final getUrl = '$redirectUrl?data=$encodedData';

      print('🔗 [OfflineSync] Enviando via GET para: ${getUrl.substring(0, 100)}...');

      final getResponse = await http.get(
        Uri.parse(getUrl),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Flutter-App/1.0',
        },
      );

      print('📡 [OfflineSync] Status após GET: ${getResponse.statusCode}');

      if (getResponse.statusCode >= 200 && getResponse.statusCode < 300) {
        return _processResponse(getResponse, action, items.length);
      } else {
        throw Exception('Erro HTTP ${getResponse.statusCode} no GET após redirecionamento');
      }
    } catch (e) {
      print('❌ [OfflineSync] Erro no GET após redirect: $e');
      rethrow;
    }
  }
  /// ✅ PROCESSAR RESPOSTA DO GOOGLE SHEETS
  void _processResponse(http.Response response, String action, int itemCount) {
    try {
      print('📥 [OfflineSync] Processando resposta...');
      print('📄 [OfflineSync] Body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...');

      final body = jsonDecode(response.body);

      if (body['success'] == true) {
        print('✅ [OfflineSync] $action ($itemCount itens) enviados com sucesso!');
        return;
      }

      final message = body['message'] ?? 'Erro desconhecido';
      throw Exception('Erro no Script: $message');

    } catch (e) {
      if (e is FormatException) {
        print('⚠️ [OfflineSync] Resposta não é JSON válido');
        print('📄 [OfflineSync] Conteúdo: ${response.body}');
        // Se não for JSON mas status foi 200, considerar sucesso
        if (response.statusCode >= 200 && response.statusCode < 300) {
          print('✅ [OfflineSync] Considerando sucesso baseado no status HTTP');
          return;
        }
      }
      rethrow;
    }
  }

  /// ✅ MÉTODO AUXILIAR PARA DIAGNÓSTICO
  Future<void> testConnection() async {
    print('🔍 [OfflineSync] Testando conexão com Google Sheets...');

    final client = http.Client();

    try {
      final testData = {
        'action': 'testConnection',
        'people': [{'timestamp': DateTime.now().toIso8601String()}],
      };

      final request = http.Request('POST', Uri.parse(_sheetsWebhook))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'application/json'
        ..headers['User-Agent'] = 'Flutter-App/1.0'
        ..body = jsonEncode(testData);

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      print('📡 [OfflineSync] Status: ${response.statusCode}');
      print('📄 [OfflineSync] Response: ${response.body}');

      if (response.statusCode == 302) {
        print('🔄 [OfflineSync] Detectado redirecionamento 302');
        final redirectUrl = response.headers['location'];
        print('🔗 [OfflineSync] URL de redirect: $redirectUrl');

        // Testar o redirect também
        final redirectResponse = await http.post(
          Uri.parse(redirectUrl!),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'Flutter-App/1.0',
          },
          body: jsonEncode(testData),
        );

        print('📡 [OfflineSync] Status após redirect: ${redirectResponse.statusCode}');
        print('📄 [OfflineSync] Response após redirect: ${redirectResponse.body}');
      }

    } catch (e) {
      print('❌ [OfflineSync] Erro no teste: $e');
    } finally {
      client.close();
    }
  }
}