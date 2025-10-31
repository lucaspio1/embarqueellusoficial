import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:embarqueellus/database/database_helper.dart';

/// Serviço para sincronizar alunos do Google Sheets (com tratamento de redirecionamento 302 → GET)
class AlunosSyncService {
  static final AlunosSyncService instance = AlunosSyncService._internal();
  AlunosSyncService._internal();

  final _db = DatabaseHelper.instance;

  final String _apiUrl =
      'https://script.google.com/macros/s/AKfycbzWUgnxCHr_60E2v8GEc8VyJrarq5JMp0nSIXDFKQsJb8yYXygocuqeeLiif_3HJc8A/exec';

  /// Sincroniza PESSOAS da aba PESSOAS do Google Sheets (todos com embeddings)
  Future<SyncResult> syncPessoasFromSheets() async {
    try {
      print('🔄 [PessoasSync] Iniciando sincronização de PESSOAS (com embeddings)...');

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(_apiUrl))
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
            body: jsonEncode({'action': 'getAllPeople'}),
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
      print(stack);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  Future<SyncResult> syncAlunosFromSheets() async {
    try {
      print('🔄 [AlunosSync] Iniciando sincronização de alunos...');

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(_apiUrl))
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
        print('🔁 [AlunosSync] Redirecionando manualmente para: $redirectedUrl');

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
            body: jsonEncode({'action': 'getAllStudents'}),
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
      print('❌ [AlunosSync] Erro geral: $e');
      print(stack);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  Future<SyncResult> _processarRespostaPessoas(http.Response response) async {
    try {
      print('📦 [PessoasSync] Response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}...');

      final data = jsonDecode(response.body);
      print('📦 [PessoasSync] Decoded data: success=${data['success']}, data length=${data['data']?.length ?? 0}');

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
          // 🔽 NOVA LÓGICA: Salvar na tabela pessoas_facial ao invés de alunos
          // Pessoas vêm da aba "Pessoas" e já têm facial cadastrada

          // Processar embedding se existir
          if (pessoa['embedding'] != null && pessoa['embedding'] != '') {
            try {
              List<double> embedding;

              // Log para debug
              print('🔍 [Debug] Processando embedding para ${pessoa['nome']} (CPF: ${pessoa['cpf']})');
              print('🔍 [Debug] Tipo do embedding: ${pessoa['embedding'].runtimeType}');

              // Se o embedding vier como string, fazer parse
              if (pessoa['embedding'] is String) {
                final embeddingStr = pessoa['embedding'] as String;

                // Verificar se é uma string vazia ou data (formato inválido)
                if (embeddingStr.isEmpty || embeddingStr.contains('T') || embeddingStr.length < 10) {
                  print('⚠️ [${pessoa['cpf']}] Embedding inválido (string vazia ou formato incorreto)');
                  continue;
                }

                try {
                  final embeddingList = jsonDecode(embeddingStr);
                  if (embeddingList is! List) {
                    print('⚠️ [${pessoa['cpf']}] Embedding não é um array: $embeddingList');
                    continue;
                  }
                  embedding = List<double>.from(embeddingList);
                } catch (e) {
                  print('⚠️ [${pessoa['cpf']}] Erro ao fazer parse do embedding string: $e');
                  continue;
                }
              } else if (pessoa['embedding'] is List) {
                embedding = List<double>.from(pessoa['embedding']);
              } else {
                print('⚠️ [${pessoa['cpf']}] Tipo de embedding não suportado: ${pessoa['embedding'].runtimeType}');
                continue;
              }

              // Validar que o embedding tem tamanho adequado (geralmente 128 ou 512 dimensões)
              if (embedding.isEmpty || embedding.length < 50) {
                print('⚠️ [${pessoa['cpf']}] Embedding com tamanho suspeito: ${embedding.length} dimensões');
                continue;
              }

              // Salvar na tabela pessoas_facial (nova tabela)
              await _db.upsertPessoaFacial({
                'cpf': pessoa['cpf'] ?? '',
                'nome': pessoa['nome'] ?? '',
                'email': pessoa['email'] ?? '',
                'telefone': pessoa['telefone'] ?? '',
                'turma': pessoa['turma'] ?? '',
                'embedding': jsonEncode(embedding),
                'facial_status': 'CADASTRADA',
              });

              // Também salvar na tabela embeddings antiga para compatibilidade
              await _db.insertEmbedding({
                'cpf': pessoa['cpf'] ?? '',
                'nome': pessoa['nome'] ?? '',
                'embedding': embedding,
              });

              countPessoas++;
              countEmbeddings++;
              print('✅ [${pessoa['cpf']}] Pessoa e embedding salvos com sucesso (${embedding.length} dimensões)');
            } catch (e, stack) {
              print('❌ [${pessoa['cpf']}] Erro ao processar pessoa/embedding: $e');
              print('Stack: $stack');
            }
          } else {
            print('⚠️ [${pessoa['cpf']}] Pessoa ${pessoa['nome']} não tem embedding');
          }
        } catch (e) {
          print('❌ Erro ao salvar pessoa ${pessoa['cpf']} - ${pessoa['nome']}: $e');
        }
      }

      print('✅ [$countPessoas] pessoas sincronizadas | [$countEmbeddings] embeddings salvos');
      return SyncResult(
        success: true,
        count: countPessoas,
        message: '$countPessoas pessoas e $countEmbeddings embeddings sincronizados'
      );
    } catch (e) {
      print('❌ [ProcessarRespostaPessoas] Erro: $e');
      print(response.body);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  Future<SyncResult> _processarResposta(http.Response response) async {
    try {
      print('📦 [AlunosSync] Response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}...');

      final data = jsonDecode(response.body);
      print('📦 [AlunosSync] Decoded data: success=${data['success']}, data length=${data['data']?.length ?? 0}');

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
            'email': aluno['email'] ?? '',
            'telefone': aluno['telefone'] ?? '',
            'turma': aluno['turma'] ?? '',
            'facial': aluno['facial_status'],
            'tem_qr': aluno['tem_qr'] ?? aluno['pulseira'] ?? 'NAO',
          };
          print('💾 [AlunosSync] Salvando aluno: ${alunoData['nome']} (${alunoData['cpf']})');
          await _db.upsertAluno(alunoData);
          count++;
        } catch (e) {
          print('❌ Erro ao salvar aluno ${aluno['nome']}: $e');
        }
      }

      print('✅ [$count] alunos sincronizados com sucesso');
      return SyncResult(success: true, count: count, message: 'Alunos sincronizados');
    } catch (e) {
      print('❌ [ProcessarResposta] Erro: $e');
      print(response.body);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  /// Verifica se há alunos locais salvos
  Future<bool> temAlunosLocais() async {
    try {
      final alunos = await _db.getAllAlunos();
      return alunos.isNotEmpty;
    } catch (e) {
      print('❌ [AlunosSync] Erro ao verificar alunos locais: $e');
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
