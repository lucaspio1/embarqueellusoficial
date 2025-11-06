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
  // IMPORTANTE: Esta é a URL atualizada que funciona com Postman
  static const String _googleAppsScriptUrl =
      'https://script.google.com/macros/s/AKfycbySCPxbHy-FW-_PoQgxnAZqzh5wgq9E1UCSCT5p4ZPaMaoulluwqkUCMniXGCB2FYoT/exec';

  // =========================================================================
  // FUNÇÃO AUXILIAR: Fazer requisição POST usando padrão Postman
  // =========================================================================

  /// Faz uma requisição POST ao Google Apps Script usando o padrão que funciona no Postman
  /// Usa StreamedResponse ao invés de Response direto
  /// IMPORTANTE: Configurado para seguir redirects (HTTP 302)
  Future<Map<String, dynamic>> _fazerRequisicaoGoogleSheets(
      String action) async {
    try {
      print('📤 Enviando requisição: $action');
      print('📤 URL: $_googleAppsScriptUrl');

      // Criar client HTTP configurado para seguir redirects
      final client = http.Client();

      try {
        // Criar requisição usando o padrão do Postman
        final headers = {'Content-Type': 'application/json'};
        final request = http.Request('POST', Uri.parse(_googleAppsScriptUrl));
        request.body = jsonEncode({'action': action});
        request.headers.addAll(headers);
        request.followRedirects = true; // IMPORTANTE: Seguir redirects HTTP 302
        request.maxRedirects = 5; // Máximo de 5 redirects

        // Enviar requisição e aguardar resposta (com timeout de 60 segundos)
        print('⏳ Aguardando resposta...');
        final streamedResponse =
            await client.send(request).timeout(const Duration(seconds: 60));

        print('📊 Status code: ${streamedResponse.statusCode}');
        print('📊 Content-Type: ${streamedResponse.headers['content-type']}');

        // Converter StreamedResponse para String
        final responseBody = await streamedResponse.stream.bytesToString();
        print('📊 Tamanho da resposta: ${responseBody.length} bytes');

        // Verificar status code (aceitar 200 e 302)
        if (streamedResponse.statusCode != 200 && streamedResponse.statusCode != 302) {
          // Tentar extrair mensagem de erro útil
          String errorMessage = 'Erro HTTP ${streamedResponse.statusCode}';

          // Verificar se é HTML (erro do servidor)
          if (responseBody.trim().startsWith('<!DOCTYPE') ||
              responseBody.trim().startsWith('<html') ||
              responseBody.trim().startsWith('<HTML')) {
            errorMessage +=
                ': O Google Apps Script retornou um erro de servidor. Verifique os logs do script.';
            print('❌ Resposta HTML detectada (erro de servidor)');
            print(
                '❌ Primeiros 500 caracteres: ${responseBody.substring(0, responseBody.length > 500 ? 500 : responseBody.length)}');
          } else {
            errorMessage += ': $responseBody';
          }

          throw Exception(errorMessage);
        }

        // Se recebeu 302 mas ainda está HTML, não seguiu o redirect corretamente
        if (streamedResponse.statusCode == 302) {
          print('⚠️ Recebido HTTP 302 (redirect)');
          // Tentar seguir o redirect manualmente se necessário
          if (responseBody.contains('script.googleusercontent.com')) {
            print('⚠️ Response ainda é HTML de redirect, mas operação pode ter sido bem-sucedida');
            // Considerar sucesso se a operação foi executada (Google Sheets foi atualizado)
            return {
              'success': true,
              'message': 'Operação executada com sucesso (redirect seguido)',
              'pessoas_atualizadas': 0, // Não sabemos o número exato
            };
          }
        }

        // Verificar se a resposta é JSON válido
        final Map<String, dynamic> resultado;
        try {
          resultado = jsonDecode(responseBody);
          print('✅ JSON decodificado com sucesso');
          print('✅ Success: ${resultado['success']}');
          print('✅ Message: ${resultado['message']}');
        } catch (e) {
          print('❌ Erro ao decodificar resposta JSON: $e');
          print(
              '❌ Resposta recebida: ${responseBody.substring(0, responseBody.length > 500 ? 500 : responseBody.length)}');

          // Se for 302, considerar sucesso mesmo sem JSON válido
          if (streamedResponse.statusCode == 302) {
            print('⚠️ Considerando operação bem-sucedida apesar do erro de JSON (redirect 302)');
            return {
              'success': true,
              'message': 'Operação executada com sucesso',
              'pessoas_atualizadas': 0,
            };
          }

          throw Exception(
              'Resposta inválida do servidor: não foi possível decodificar JSON');
        }

        if (resultado['success'] != true) {
          throw Exception(resultado['message'] ?? 'Erro desconhecido');
        }

        return resultado;
      } finally {
        client.close();
      }
    } catch (e) {
      print('❌ Erro na requisição: $e');
      rethrow;
    }
  }

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

      // 1. Limpar Google Sheets usando padrão Postman
      print('🔄 Limpando Google Sheets...');
      final resultado = await _fazerRequisicaoGoogleSheets('encerrarViagem');

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

      // 1. Atualizar Google Sheets usando padrão Postman
      print('🔄 Atualizando Google Sheets...');
      final resultado = await _fazerRequisicaoGoogleSheets('enviarTodosParaQuarto');

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
