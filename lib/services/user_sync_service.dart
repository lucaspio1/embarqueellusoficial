import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:embarqueellus/database/database_helper.dart';

class UserSyncService {
  static final UserSyncService instance = UserSyncService._internal();
  UserSyncService._internal();

  // URL do GAS /exec
  final String _apiBase = 'https://script.google.com/macros/s/AKfycbzWUgnxCHr_60E2v8GEc8VyJrarq5JMp0nSIXDFKQsJb8yYXygocuqeeLiif_3HJc8A/exec';
  final _db = DatabaseHelper.instance;

  String _hashSenha(String senha) => sha256.convert(utf8.encode(senha)).toString();

  Future<SyncResult> syncUsuariosFromSheets() async {
    print('🔄 [UserSync] Iniciando sincronização de usuários...');
    final uri = Uri.parse('$_apiBase?action=getAllUsers');

    http.Response resp;
    try {
      // GET segue redirecionamentos automaticamente
      resp = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      print('❌ [UserSync] Falha de conexão: $e');
      return SyncResult(success: false, message: 'Falha de conexão', count: 0);
    }

    print('📥 [UserSync] Status: ${resp.statusCode}');

    if (resp.statusCode != 200) {
      print('📥 [UserSync] Body (não-200): ${resp.body}');
      return SyncResult(success: false, message: 'Erro HTTP: ${resp.statusCode}', count: 0);
    }

    dynamic data;
    try {
      data = jsonDecode(resp.body);
    } catch (e) {
      print('❌ [UserSync] JSON inválido: $e');
      print('📥 [UserSync] Body: ${resp.body}');
      return SyncResult(success: false, message: 'JSON inválido', count: 0);
    }

    if (data is Map && data['success'] == true && data['users'] is List) {
      final usuarios = (data['users'] as List);

      print('📥 [UserSync] Recebidos ${usuarios.length} usuários');
      await _db.deleteAllUsuarios();

      for (final u in usuarios) {
        if (u is! Map) continue;
        final usuario = Map<String, dynamic>.from(u);
        final senhaOriginal = (usuario['senha'] ?? '').toString();
        final senhaHash = _hashSenha(senhaOriginal);

        await _db.upsertUsuario({
          'user_id': (usuario['id'] ?? '').toString(),
          'nome': usuario['nome'],
          'cpf': (usuario['cpf'] ?? '').toString().trim(),
          'senha_hash': senhaHash,
          'perfil': (usuario['perfil'] ?? 'USUARIO').toString().toUpperCase(),
          'ativo': 1,
        });
      }

      final total = await _db.getTotalUsuarios();
      print('✅ [UserSync] $total usuários sincronizados');
      return SyncResult(success: true, message: '$total usuários sincronizados', count: total);
    }

    print('⚠️ [UserSync] Resposta sem usuários');
    print('📥 [UserSync] Body: ${resp.body}');
    return SyncResult(success: false, message: 'Nenhum usuário encontrado', count: 0);
  }

  bool verificarSenha(String senha, String senhaHash) => _hashSenha(senha) == senhaHash;

  Future<bool> temUsuariosLocais() async => (await _db.getTotalUsuarios()) > 0;
}

class SyncResult {
  final bool success;
  final String message;
  final int count;

  SyncResult({required this.success, required this.message, required this.count});
}
