import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:embarqueellus/database/database_helper.dart';

/// Serviço para ações críticas do sistema
/// ATENÇÃO: Métodos destrutivos que apagam dados permanentemente!
class AcoesCriticasService {
  static final AcoesCriticasService _instance = AcoesCriticasService._internal();
  factory AcoesCriticasService() => _instance;
  static AcoesCriticasService get instance => _instance;

  AcoesCriticasService._internal();

  final _db = DatabaseHelper.instance;

  // URL do Google Apps Script (deve estar no .env ou configuração)
  static const String _googleAppsScriptUrl =
      'https://script.google.com/macros/s/AKfycbxHvpM1yg1oLQT1kwF_d8z9TxiAKa8Vqk5QLFO7AJEBdQtC_VUCNr2MJ-_qZ6ltbyW4/exec';

  // =========================================================================
  // 1. ENCERRAR VIAGEM - Limpa TUDO (Google Sheets + Banco Local)
  // =========================================================================

  /// Encerra a viagem: Limpa TODAS as abas do Google Sheets (Pessoas, Logs, Alunos)
  /// E limpa TODOS os dados do banco de dados local
  ///
  /// ATENÇÃO: OPERAÇÃO IRREVERSÍVEL! Todos os dados serão perdidos!
  ///
  /// Returns: Resultado da operação
  Future<AcaoCriticaResult> encerrarViagem() async {
    try {
      print('🔴 [CRÍTICO] Iniciando encerramento de viagem...');

      // 1. Limpar Google Sheets
      print('🔄 Limpando Google Sheets...');
      final response = await http.post(
        Uri.parse(_googleAppsScriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'encerrarViagem'}),
      ).timeout(const Duration(seconds: 30));

      print('📊 Status code: ${response.statusCode}');
      print('📊 Content-Type: ${response.headers['content-type']}');

      if (response.statusCode != 200) {
        // Tentar extrair mensagem de erro útil
        String errorMessage = 'Erro HTTP ${response.statusCode}';

        // Verificar se é HTML (erro do servidor)
        if (response.body.trim().startsWith('<!DOCTYPE') ||
            response.body.trim().startsWith('<html')) {
          errorMessage +=
              ': O Google Apps Script retornou um erro de servidor. Verifique os logs do script.';
          print('❌ Resposta HTML detectada (erro de servidor)');
          print('❌ Primeiros 500 caracteres: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
        } else {
          errorMessage += ': ${response.body}';
        }

        throw Exception(errorMessage);
      }

      // Verificar se a resposta é JSON válido
      final Map<String, dynamic> resultado;
      try {
        resultado = jsonDecode(response.body);
      } catch (e) {
        print('❌ Erro ao decodificar resposta JSON: $e');
        print('❌ Resposta recebida: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
        throw Exception(
            'Resposta inválida do servidor: não foi possível decodificar JSON');
      }

      if (resultado['success'] != true) {
        throw Exception(resultado['message'] ?? 'Erro desconhecido');
      }

      print('✅ Google Sheets limpo com sucesso');

      // 2. Limpar banco de dados local
      print('🔄 Limpando banco de dados local...');
      await _limparBancoDadosLocal();
      print('✅ Banco de dados local limpo');

      print('✅ [CRÍTICO] Viagem encerrada com sucesso!');

      return AcaoCriticaResult(
        success: true,
        message: 'Viagem encerrada com sucesso! Todos os dados foram removidos.',
        detalhes: {
          'google_sheets': resultado,
          'banco_local': 'Limpo',
        },
      );
    } catch (e) {
      print('❌ [CRÍTICO] Erro ao encerrar viagem: $e');
      return AcaoCriticaResult(
        success: false,
        message: 'Erro ao encerrar viagem: $e',
      );
    }
  }

  /// Limpa todas as tabelas do banco de dados local
  Future<void> _limparBancoDadosLocal() async {
    final db = await _db.database;

    // Limpar todas as tabelas
    await db.delete('pessoas_facial');
    await db.delete('logs');
    await db.delete('alunos');
    await db.delete('offline_sync_queue');

    print('✅ Tabelas locais limpas: pessoas_facial, logs, alunos, offline_sync_queue');
  }

  // =========================================================================
  // 2. ENVIAR TODOS PARA QUARTO
  // =========================================================================

  /// Envia todas as pessoas para QUARTO (atualiza movimentação)
  /// Atualiza no Google Sheets E no banco local
  ///
  /// Returns: Resultado da operação
  Future<AcaoCriticaResult> enviarTodosParaQuarto() async {
    try {
      print('🔄 [CRÍTICO] Enviando todos para QUARTO...');

      // 1. Atualizar Google Sheets
      print('🔄 Atualizando Google Sheets...');
      final response = await http.post(
        Uri.parse(_googleAppsScriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'enviarTodosParaQuarto'}),
      ).timeout(const Duration(seconds: 30));

      print('📊 Status code: ${response.statusCode}');
      print('📊 Content-Type: ${response.headers['content-type']}');

      if (response.statusCode != 200) {
        // Tentar extrair mensagem de erro útil
        String errorMessage = 'Erro HTTP ${response.statusCode}';

        // Verificar se é HTML (erro do servidor)
        if (response.body.trim().startsWith('<!DOCTYPE') ||
            response.body.trim().startsWith('<html')) {
          errorMessage +=
              ': O Google Apps Script retornou um erro de servidor. Verifique os logs do script.';
          print('❌ Resposta HTML detectada (erro de servidor)');
          print('❌ Primeiros 500 caracteres: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
        } else {
          errorMessage += ': ${response.body}';
        }

        throw Exception(errorMessage);
      }

      // Verificar se a resposta é JSON válido
      final Map<String, dynamic> resultado;
      try {
        resultado = jsonDecode(response.body);
      } catch (e) {
        print(
            '❌ Erro ao decodificar resposta JSON: $e');
        print('❌ Resposta recebida: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
        throw Exception(
            'Resposta inválida do servidor: não foi possível decodificar JSON');
      }

      if (resultado['success'] != true) {
        throw Exception(resultado['message'] ?? 'Erro desconhecido');
      }

      print('✅ Google Sheets atualizado: ${resultado['pessoas_atualizadas']} pessoas');

      // 2. Atualizar banco de dados local
      print('🔄 Atualizando banco de dados local...');
      final pessoasAtualizadas = await _atualizarTodasPessoasParaQuarto();
      print('✅ Banco local atualizado: $pessoasAtualizadas pessoas');

      print('✅ [CRÍTICO] Todos enviados para QUARTO com sucesso!');

      return AcaoCriticaResult(
        success: true,
        message: 'Todas as pessoas foram enviadas para QUARTO',
        detalhes: {
          'google_sheets': resultado,
          'banco_local_pessoas': pessoasAtualizadas,
        },
      );
    } catch (e) {
      print('❌ [CRÍTICO] Erro ao enviar para quarto: $e');
      return AcaoCriticaResult(
        success: false,
        message: 'Erro ao enviar para quarto: $e',
      );
    }
  }

  /// Atualiza todas as pessoas no banco local para movimentação = QUARTO
  Future<int> _atualizarTodasPessoasParaQuarto() async {
    final db = await _db.database;

    final result = await db.update(
      'pessoas_facial',
      {
        'movimentacao': 'QUARTO',
        'updated_at': DateTime.now().toIso8601String(),
      },
    );

    return result; // Retorna número de linhas atualizadas
  }
}

/// Resultado de uma ação crítica
class AcaoCriticaResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? detalhes;

  AcaoCriticaResult({
    required this.success,
    required this.message,
    this.detalhes,
  });

  @override
  String toString() {
    return 'AcaoCriticaResult(success: $success, message: $message, detalhes: $detalhes)';
  }
}
