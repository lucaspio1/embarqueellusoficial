import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:embarqueellus/database/database_helper.dart';

/// Serviço para sincronizar alunos do Google Sheets (com tratamento de redirecionamento 302 → GET)
class AlunosSyncService {
  static final AlunosSyncService instance = AlunosSyncService._internal();
  AlunosSyncService._internal();

  final _db = DatabaseHelper.instance;

  final String _apiUrl =
      'https://script.google.com/macros/s/AKfycbwb9dYG8PrcEnWxLUHEoGxOgpKd5NFqN8QAaluNJ8DLKWrdBssKdK2VfwHSAW6gDLhf/exec';

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
      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        final msg = data['message'] ?? 'Erro desconhecido';
        return SyncResult(success: false, count: 0, message: msg);
      }

      final pessoas = data['data'] ?? [];
      int countAlunos = 0;
      int countEmbeddings = 0;

      for (final pessoa in pessoas) {
        try {
          // Salvar na tabela alunos
          await _db.upsertAluno({
            'cpf': pessoa['cpf'] ?? '',
            'nome': pessoa['nome'] ?? '',
            'email': pessoa['email'] ?? '',
            'telefone': pessoa['telefone'] ?? '',
            'turma': pessoa['turma'] ?? '',
            'facial': 'CADASTRADA', // Vem da aba PESSOAS, então já tem facial
          });
          countAlunos++;

          // Salvar embedding se existir
          if (pessoa['embedding'] != null) {
            List<double> embedding;

            // Se o embedding vier como string, fazer parse
            if (pessoa['embedding'] is String) {
              final embeddingList = jsonDecode(pessoa['embedding']);
              embedding = List<double>.from(embeddingList);
            } else if (pessoa['embedding'] is List) {
              embedding = List<double>.from(pessoa['embedding']);
            } else {
              print('⚠️ Embedding inválido para ${pessoa['nome']}');
              continue;
            }

            await _db.insertEmbedding({
              'cpf': pessoa['cpf'] ?? '',
              'nome': pessoa['nome'] ?? '',
              'embedding': embedding,
            });
            countEmbeddings++;
          }
        } catch (e) {
          print('❌ Erro ao salvar pessoa ${pessoa['nome']}: $e');
        }
      }

      print('✅ [$countAlunos] pessoas sincronizadas | [$countEmbeddings] embeddings salvos');
      return SyncResult(
        success: true,
        count: countAlunos,
        message: '$countAlunos pessoas e $countEmbeddings embeddings sincronizados'
      );
    } catch (e) {
      print('❌ [ProcessarRespostaPessoas] Erro: $e');
      print(response.body);
      return SyncResult(success: false, count: 0, message: e.toString());
    }
  }

  Future<SyncResult> _processarResposta(http.Response response) async {
    try {
      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        final msg = data['message'] ?? 'Erro desconhecido';
        return SyncResult(success: false, count: 0, message: msg);
      }

      final alunos = data['data'] ?? [];
      int count = 0;
      for (final aluno in alunos) {
        try {
          await _db.upsertAluno({
            'cpf': aluno['cpf'] ?? '',
            'nome': aluno['nome'] ?? '',
            'email': aluno['email'] ?? '',
            'telefone': aluno['telefone'] ?? '',
            'turma': aluno['turma'] ?? '',
            'facial': aluno['facial_status'],
            'tem_qr': aluno['tem_qr'] ?? aluno['pulseira'] ?? 'NAO', // Campo para controle de QR/pulseira
          });
          count++;
        } catch (e) {
          print('❌ Erro ao salvar aluno: $e');
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
