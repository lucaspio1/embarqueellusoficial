import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:embarqueellus/database/database_helper.dart';

/// Serviço para sincronizar logs do Google Sheets (aba LOGS)
class LogsSyncService {
  static final LogsSyncService instance = LogsSyncService._internal();
  LogsSyncService._internal();

  final _db = DatabaseHelper.instance;

  final String _apiUrl =
      'https://script.google.com/macros/s/AKfycby14ubSOGVMr7Wzoof-r_pnNKUESSMvhk20z7NO2ZBqvS-DdiErwprhaEQ8Ay99IkIa/exec';

  /// Sincroniza LOGS da aba LOGS do Google Sheets
  Future<SyncResult> syncLogsFromSheets() async {
    try {
      print('🔄 [LogsSync] Iniciando sincronização de logs...');

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(_apiUrl))
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

        http.Response redirectedResponse;

        try {
          redirectedResponse = await http.post(
            Uri.parse(redirectedUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-Requested-With': 'XMLHttpRequest',
              'User-Agent': 'PostmanRuntime/7.32.3',
            },
            body: jsonEncode({'action': 'getAllLogs'}),
          );

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
        } catch (e) {
          print('❌ [Redirected] Erro ao seguir redirect: $e');
          return SyncResult(success: false, count: 0, message: 'Erro ao seguir redirect: $e');
        }

        print('📡 [Redirected] Status: ${redirectedResponse.statusCode}');
        return await _processarResposta(redirectedResponse);
      }

      if (response.statusCode == 200) {
        return await _processarResposta(response);
      }

      return SyncResult(
        success: false,
        count: 0,
        message: 'Erro HTTP ${response.statusCode}',
      );
    } catch (e, stack) {
      print('❌ [LogsSync] Erro geral: $e');
      print(stack);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  Future<SyncResult> _processarResposta(http.Response response) async {
    try {
      print('📦 [LogsSync] Response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}...');

      final data = jsonDecode(response.body);
      print('📦 [LogsSync] Decoded data: success=${data['success']}, data length=${data['data']?.length ?? 0}');

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
          // Parse do timestamp - pode vir como string ou já estar no formato correto
          DateTime timestamp;
          try {
            if (log['timestamp'] is String) {
              timestamp = DateTime.parse(log['timestamp']);
            } else if (log['timestamp'] is DateTime) {
              timestamp = log['timestamp'];
            } else {
              // Se não houver timestamp válido, usar a data atual
              timestamp = DateTime.now();
            }
          } catch (e) {
            print('⚠️ Erro ao fazer parse do timestamp: $e, usando data atual');
            timestamp = DateTime.now();
          }

          final personName = log['person_name'] ?? log['nome'] ?? '';
          print('💾 [LogsSync] Salvando log: $personName (${log['cpf']}) - ${log['tipo']}');

          await _db.insertLog(
            cpf: log['cpf'] ?? '',
            personName: personName,
            timestamp: timestamp,
            confidence: (log['confidence'] ?? 0.0).toDouble(),
            tipo: log['tipo'] ?? 'FACIAL',
            operadorNome: log['operador_nome'] ?? log['operador'] ?? '',
          );
          count++;
        } catch (e) {
          // Ignora duplicatas (constraint UNIQUE)
          if (!e.toString().contains('UNIQUE constraint failed')) {
            print('❌ Erro ao salvar log ${log['person_name']}: $e');
          } else {
            print('⚠️ Log duplicado ignorado: ${log['person_name']}');
          }
        }
      }

      print('✅ [$count] logs sincronizados com sucesso');
      return SyncResult(success: true, count: count, message: '$count logs sincronizados');
    } catch (e) {
      print('❌ [ProcessarResposta] Erro: $e');
      print(response.body);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  /// Verifica se há logs locais salvos
  Future<bool> temLogsLocais() async {
    try {
      final logs = await _db.getAllLogs();
      return logs.isNotEmpty;
    } catch (e) {
      print('❌ [LogsSync] Erro ao verificar logs locais: $e');
      return false;
    }
  }
}

class SyncResult {
  final bool success;
  final int count;
  final String message;

  SyncResult({required this.success, required this.count, required this.message});
}
