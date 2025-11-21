// lib/services/quartos_sync_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/config/app_config.dart';

class QuartosSyncService {
  static final QuartosSyncService instance = QuartosSyncService._internal();
  QuartosSyncService._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;
  String get _sheetsWebhook => AppConfig.instance.googleAppsScriptUrl;

  /// Sincroniza quartos da aba QUARTOS do Google Sheets
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

      // Fazer requisição ao Google Apps Script
      final response = await http.post(
        Uri.parse(_sheetsWebhook),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'action': 'getQuartos',
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);

        if (body is Map && body['success'] == true) {
          final List<dynamic> quartos = (body['data'] as List?) ?? [];
          int count = 0;

          // Limpar quartos antigos antes de inserir novos
          // await _db.clearQuartos();

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
      } else {
        print('❌ [QuartosSync] HTTP ${response.statusCode}: ${response.body}');
        return SyncResult(
          success: false,
          message: 'Erro HTTP ${response.statusCode}',
          count: 0,
        );
      }
    } catch (e) {
      print('❌ [QuartosSync] Erro ao sincronizar quartos: $e');
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

/// Resultado de sincronização
class SyncResult {
  final bool success;
  final String message;
  final int count;

  SyncResult({
    required this.success,
    required this.message,
    required this.count,
  });
}
