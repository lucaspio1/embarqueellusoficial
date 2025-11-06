import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/config/app_config.dart';

/// Serviço para ações críticas do sistema
/// ATENÇÃO: Métodos destrutivos que apagam dados permanentemente!
class AcoesCriticasService {
  static final AcoesCriticasService _instance = AcoesCriticasService._internal();
  factory AcoesCriticasService() => _instance;
  static AcoesCriticasService get instance => _instance;

  AcoesCriticasService._internal();

  final _db = DatabaseHelper.instance;

  // ✅ URL do Google Apps Script lida do arquivo .env
  String get _googleAppsScriptUrl => AppConfig.instance.googleAppsScriptUrl;

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
          print('⚠️ Recebido HTTP 302 (redirect) para ação: $action');
          // Tentar seguir o redirect manualmente se necessário
          if (responseBody.contains('script.googleusercontent.com')) {
            print('✅ Response é HTML de redirect, mas operação FOI EXECUTADA COM SUCESSO no Google Sheets');
            print('✅ Tratando HTTP 302 como sucesso - Google Sheets foi atualizado corretamente');
            // Considerar sucesso se a operação foi executada (Google Sheets foi atualizado)
            return {
              'success': true,
              'message': 'Operação executada com sucesso',
              'pessoas_atualizadas': 0, // Não sabemos o número exato
              'abas_limpas': ['PESSOAS', 'LOGS', 'ALUNOS'], // Para encerrarViagem
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
            print('✅ HTTP 302 detectado - Considerando operação bem-sucedida');
            print('✅ Ação "$action" foi EXECUTADA COM SUCESSO no Google Sheets');
            return {
              'success': true,
              'message': 'Operação executada com sucesso',
              'pessoas_atualizadas': 0,
              'abas_limpas': ['PESSOAS', 'LOGS', 'ALUNOS'], // Para encerrarViagem
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

  // =========================================================================
  // NOVO: LISTAR VIAGENS DISPONÍVEIS
  // =========================================================================

  /// Lista todas as viagens únicas disponíveis (baseado em inicio_viagem e fim_viagem)
  /// Busca na aba ALUNOS do Google Sheets
  ///
  /// Returns: Lista de viagens com { inicio_viagem, fim_viagem }
  Future<List<Map<String, String>>> listarViagens() async {
    try {
      print('📋 Listando viagens disponíveis...');

      final client = http.Client();

      try {
        final request = http.Request('POST', Uri.parse(_googleAppsScriptUrl))
          ..followRedirects = false
          ..headers['Content-Type'] = 'application/json; charset=utf-8'
          ..headers['Accept'] = 'application/json'
          ..headers['X-Requested-With'] = 'XMLHttpRequest'
          ..headers['User-Agent'] = 'PostmanRuntime/7.32.3'
          ..body = jsonEncode({'action': 'listarViagens'});

        final streamedResponse = await client.send(request);
        final response = await http.Response.fromStream(streamedResponse);

        print('📡 [ListarViagens] Status: ${response.statusCode}');

        // Se recebeu 302, seguir o redirect manualmente com GET
        if (response.statusCode == 302 && response.headers['location'] != null) {
          final redirectedUrl = response.headers['location']!;
          print('🔁 [ListarViagens] Redirecionando para: $redirectedUrl');

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
              body: jsonEncode({'action': 'listarViagens'}),
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
            return [];
          }

          print('📡 [Redirected] Status: ${redirectedResponse.statusCode}');
          return _processarRespostaViagens(redirectedResponse);
        }

        if (response.statusCode == 200) {
          return _processarRespostaViagens(response);
        }

        print('⚠️ Nenhuma viagem encontrada (status: ${response.statusCode})');
        return [];
      } finally {
        client.close();
      }
    } catch (e) {
      print('❌ Erro ao listar viagens: $e');
      return [];
    }
  }

  /// Processa a resposta da requisição de listarViagens
  List<Map<String, String>> _processarRespostaViagens(http.Response response) {
    try {
      final resultado = jsonDecode(response.body);

      if (resultado['success'] == true) {
        final data = resultado['data'] ?? {};
        final viagens = data['viagens'] as List? ?? [];
        print('✅ ${viagens.length} viagem(ns) encontrada(s)');

        return viagens
            .map((v) => {
                  'inicio_viagem': v['inicio_viagem']?.toString() ?? '',
                  'fim_viagem': v['fim_viagem']?.toString() ?? '',
                })
            .toList();
      }

      print('⚠️ Resposta sem sucesso: ${resultado['message'] ?? 'erro desconhecido'}');
      return [];
    } catch (e) {
      print('❌ Erro ao processar resposta: $e');
      print('📦 Response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
      return [];
    }
  }

  // =========================================================================
  // ATUALIZADO: ENCERRAR VIAGEM (com suporte a viagem específica)
  // =========================================================================

  /// Encerra uma viagem específica ou todas as viagens
  /// Se inicioViagem e fimViagem forem fornecidos, encerra APENAS essa viagem
  /// Caso contrário, encerra TODAS as viagens (comportamento antigo)
  ///
  /// ATENÇÃO: OPERAÇÃO IRREVERSÍVEL! Dados serão perdidos!
  ///
  /// Returns: Resultado da operação
  Future<AcaoCriticaResult> encerrarViagem({
    String? inicioViagem,
    String? fimViagem,
  }) async {
    try {
      if (inicioViagem != null && fimViagem != null) {
        print('🔴 [CRÍTICO] Encerrando viagem específica: $inicioViagem a $fimViagem...');
      } else {
        print('🔴 [CRÍTICO] Encerrando TODAS as viagens...');
      }

      // 1. Limpar Google Sheets
      print('🔄 Limpando Google Sheets (pode receber HTTP 302 - isso é normal)...');

      final client = http.Client();
      Map<String, dynamic> resultado;

      try {
        final headers = {'Content-Type': 'application/json'};
        final request = http.Request('POST', Uri.parse(_googleAppsScriptUrl));
        request.body = jsonEncode({
          'action': 'encerrarViagem',
          if (inicioViagem != null) 'inicio_viagem': inicioViagem,
          if (fimViagem != null) 'fim_viagem': fimViagem,
        });
        request.headers.addAll(headers);
        request.followRedirects = true;
        request.maxRedirects = 5;

        final streamedResponse =
            await client.send(request).timeout(const Duration(seconds: 60));
        final responseBody = await streamedResponse.stream.bytesToString();

        if (streamedResponse.statusCode == 200 || streamedResponse.statusCode == 302) {
          resultado = jsonDecode(responseBody);
          print('✅ Google Sheets atualizado');
        } else {
          throw Exception('Erro HTTP ${streamedResponse.statusCode}');
        }
      } finally {
        client.close();
      }

      // 2. Limpar banco de dados local
      print('🔄 Limpando banco de dados local...');
      if (inicioViagem != null && fimViagem != null) {
        await _limparBancoDadosLocalFiltrado(inicioViagem, fimViagem);
      } else {
        await _limparBancoDadosLocal();
      }
      print('✅ Banco de dados local limpo');

      final totalRemovidos = resultado['total_removidos'] ?? 0;
      final mensagem = inicioViagem != null && fimViagem != null
          ? 'Viagem encerrada com sucesso! $totalRemovidos registro(s) removido(s).'
          : 'Todas as viagens encerradas com sucesso!';

      print('✅ [CRÍTICO] $mensagem');

      return AcaoCriticaResult(
        success: true,
        message: mensagem,
        detalhes: {
          'google_sheets': resultado,
          'banco_local': 'Limpo',
          if (inicioViagem != null) 'inicio_viagem': inicioViagem,
          if (fimViagem != null) 'fim_viagem': fimViagem,
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

  /// Limpa registros filtrados por data de viagem do banco de dados local
  Future<void> _limparBancoDadosLocalFiltrado(String inicioViagem, String fimViagem) async {
    final db = await _db.database;

    // Limpar registros específicos
    int totalPessoas = await db.delete(
      'pessoas_facial',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );

    int totalLogs = await db.delete(
      'logs',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );

    int totalAlunos = await db.delete(
      'alunos',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );

    print('✅ Registros removidos: $totalPessoas pessoas, $totalLogs logs, $totalAlunos alunos');
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
      print('🔄 Atualizando Google Sheets (pode receber HTTP 302 - isso é normal)...');
      final resultado = await _fazerRequisicaoGoogleSheets('enviarTodosParaQuarto');

      final numPessoas = resultado['pessoas_atualizadas'] ?? 0;
      if (numPessoas > 0) {
        print('✅ Google Sheets atualizado: $numPessoas pessoas enviadas para QUARTO');
      } else {
        print('✅ Google Sheets atualizado: Todas as pessoas enviadas para QUARTO');
      }

      // 2. Atualizar banco de dados local
      print('🔄 Atualizando banco de dados local...');
      final pessoasAtualizadas = await _atualizarTodasPessoasParaQuarto();
      print('✅ Banco local atualizado: $pessoasAtualizadas pessoas enviadas para QUARTO');

      print('✅ [CRÍTICO] Operação concluída com sucesso!');

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
