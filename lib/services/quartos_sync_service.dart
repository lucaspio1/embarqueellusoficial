// lib/services/quartos_sync_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/config/app_config.dart';
import 'package:embarqueellus/services/offline_sync_service.dart';

class QuartosSyncService {
  static final QuartosSyncService instance = QuartosSyncService._internal();
  QuartosSyncService._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;
  String get _sheetsWebhook => AppConfig.instance.googleAppsScriptUrl;

  /// Sincroniza quartos da aba HOMELIST do Google Sheets
  Future<SyncResult> syncQuartosFromSheets() async {
    try {
      print('🔄 [QuartosSync] Iniciando sincronização de quartos...');

      if (_sheetsWebhook.isEmpty) {
        return SyncResult(
          success: false,
          message: 'URL do webhook não configurada',
          count: 0,
        );
      }

      // Fazer requisição ao Google Apps Script com seguimento de redirect
      final client = http.Client();
      final request = http.Request('POST', Uri.parse(_sheetsWebhook))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json; charset=utf-8'
        ..headers['Accept'] = 'application/json'
        ..headers['X-Requested-With'] = 'XMLHttpRequest'
        ..headers['User-Agent'] = 'PostmanRuntime/7.32.3'
        ..body = jsonEncode({'action': 'getQuartos'});

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      client.close();

      print('📡 [QuartosSync] Status: ${response.statusCode}');

      // Seguir redirect se necessário (302)
      if (response.statusCode == 302 && response.headers['location'] != null) {
        final redirectedUrl = response.headers['location']!;
        print('🔁 [QuartosSync] Redirecionando para: $redirectedUrl');

        http.Response redirectedResponse = await _followRedirect(redirectedUrl);
        return await _processarResposta(redirectedResponse);
      }

      // Resposta direta (200)
      if (response.statusCode == 200) {
        return await _processarResposta(response);
      }

      print('❌ [QuartosSync] HTTP ${response.statusCode}: ${response.body}');
      return SyncResult(
        success: false,
        message: 'Erro HTTP ${response.statusCode}',
        count: 0,
      );
    } catch (e) {
      print('❌ [QuartosSync] Erro ao sincronizar quartos: $e');
      return SyncResult(
        success: false,
        message: e.toString(),
        count: 0,
      );
    }
  }

  /// Segue o redirect (302) do Google Apps Script
  Future<http.Response> _followRedirect(String redirectedUrl) async {
    try {
      // Tentar POST primeiro
      http.Response redirectedResponse = await http.post(
        Uri.parse(redirectedUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'User-Agent': 'PostmanRuntime/7.32.3',
        },
        body: jsonEncode({'action': 'getQuartos'}),
      );

      // Se POST não funcionar (405), tentar GET
      if (redirectedResponse.statusCode == 405) {
        print('⚠️ [QuartosSync] POST não permitido, tentando GET...');
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
      print('❌ [QuartosSync] Erro ao seguir redirect: $e');
      rethrow;
    }
  }

  /// Processa a resposta do Google Apps Script
  Future<SyncResult> _processarResposta(http.Response response) async {
    try {
      final body = jsonDecode(response.body);

      if (body is Map && body['success'] == true) {
        final List<dynamic> quartos = (body['data'] as List?) ?? [];
        print('📊 [QuartosSync] Total de quartos recebidos: ${quartos.length}');

        // Limpar quartos antigos antes de inserir novos (evita duplicação)
        await _db.clearQuartos();
        print('🧹 [QuartosSync] Quartos antigos limpos');

        int count = 0;

        for (final q in quartos) {
          if (q is Map && q['CPF'] != null && q['Quarto'] != null) {
            try {
              await _db.upsertQuarto({
                'numero_quarto': q['Quarto']?.toString() ?? '',
                'escola': q['Escola']?.toString() ?? '',
                'nome_hospede': q['Nome do Hóspede']?.toString() ?? '',
                'cpf': q['CPF']?.toString() ?? '',
                'inicio_viagem': q['inicio_viagem']?.toString(),
                'fim_viagem': q['fim_viagem']?.toString(),
              });
              count++;
            } catch (e) {
              print('⚠️ [QuartosSync] Erro ao inserir quarto: $e');
            }
          }
        }

        print('✅ [QuartosSync] $count quartos sincronizados com sucesso!');
        return SyncResult(
          success: true,
          message: '$count quartos sincronizados',
          count: count,
        );
      } else {
        print('⚠️ [QuartosSync] Resposta sem success=true: ${response.body}');
        return SyncResult(
          success: false,
          message: 'Resposta inválida do servidor',
          count: 0,
        );
      }
    } catch (e) {
      print('❌ [QuartosSync] Erro ao processar resposta: $e');
      return SyncResult(
        success: false,
        message: e.toString(),
        count: 0,
      );
    }
  }

  /// Verifica se há quartos locais
  Future<bool> temQuartosLocais() async {
    final quartos = await _db.getAllQuartos();
    return quartos.isNotEmpty;
  }
}
