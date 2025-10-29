import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:embarqueellus/database/database_helper.dart';

class UserSyncService {
  static final UserSyncService instance = UserSyncService._internal();
  UserSyncService._internal();

  final String _apiUrl = 'https://script.google.com/macros/s/AKfycbzI8u7j02KkgYeZQJN5JxWlUy0nZ5YP7rr_r8rur1BFw0U3HcEu80PDuvjM-WRJwvHZ/exec';
  final _db = DatabaseHelper.instance;

  /// Hash de senha usando SHA-256
  String _hashSenha(String senha) {
    final bytes = utf8.encode(senha);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Sincroniza usuários da planilha LOGIN
  Future<SyncResult> syncUsuariosFromSheets() async {
    try {
      print('🔄 [UserSync] Iniciando sincronização de usuários...');

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getAllUsers'}),
      ).timeout(const Duration(seconds: 30));

      print('📥 [UserSync] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['users'] != null) {
          final usuarios = data['users'] as List;

          print('📥 [UserSync] Recebidos ${usuarios.length} usuários');

          // Limpar usuários antigos
          await _db.deleteAllUsuarios();

          // Inserir novos usuários com senha hasheada
          for (final usuario in usuarios) {
            final senhaOriginal = usuario['senha'].toString();
            final senhaHash = _hashSenha(senhaOriginal);

            await _db.upsertUsuario({
              'user_id': usuario['id'].toString(),
              'nome': usuario['nome'],
              'cpf': usuario['cpf'].toString().trim(),
              'senha_hash': senhaHash,
              'perfil': usuario['perfil'].toString().toUpperCase(),
              'ativo': 1,
            });
          }

          final total = await _db.getTotalUsuarios();
          print('✅ [UserSync] ${total} usuários sincronizados');

          return SyncResult(
            success: true,
            message: '$total usuários sincronizados',
            count: total,
          );
        } else {
          print('⚠️ [UserSync] Resposta sem usuários');
          return SyncResult(
            success: false,
            message: 'Nenhum usuário encontrado na planilha',
            count: 0,
          );
        }
      } else {
        print('❌ [UserSync] Erro HTTP: ${response.statusCode}');
        return SyncResult(
          success: false,
          message: 'Erro ao conectar: ${response.statusCode}',
          count: 0,
        );
      }
    } catch (e) {
      print('❌ [UserSync] Erro: $e');
      return SyncResult(
        success: false,
        message: 'Erro: $e',
        count: 0,
      );
    }
  }

  /// Verifica senha (compara hash)
  bool verificarSenha(String senha, String senhaHash) {
    final hashCalculado = _hashSenha(senha);
    return hashCalculado == senhaHash;
  }

  /// Verifica se existem usuários locais
  Future<bool> temUsuariosLocais() async {
    final total = await _db.getTotalUsuarios();
    return total > 0;
  }
}

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
