import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/user_sync_service.dart';

class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  final _db = DatabaseHelper.instance;
  final _userSync = UserSyncService.instance;

  // Usuário logado em cache
  Map<String, dynamic>? _usuarioLogado;

  /// Login offline usando banco de dados local
  Future<Map<String, dynamic>?> login(String cpf, String senha) async {
    try {
      print('🔐 [Auth] Tentando login offline: CPF=$cpf');

      // Garantir que a tabela de usuários existe
      await _db.ensureFacialSchema();

      // Buscar usuário no banco local
      final usuario = await _db.getUsuarioByCpf(cpf);

      if (usuario == null) {
        print('❌ [Auth] Usuário não encontrado no banco local');
        return null;
      }

      // Verificar senha
      final senhaValida = _userSync.verificarSenha(senha, usuario['senha_hash']);

      if (!senhaValida) {
        print('❌ [Auth] Senha inválida');
        return null;
      }

      // Preparar dados do usuário
      final user = {
        'id': usuario['user_id']?.toString() ?? usuario['id'].toString(),
        'nome': usuario['nome'],
        'cpf': usuario['cpf'],
        'perfil': usuario['perfil'] ?? 'USUARIO',
      };

      print('✅ [Auth] Login bem-sucedido: ${user['nome']} (${user['perfil']})');

      // Salvar usuário no cache
      _usuarioLogado = user;

      // Salvar no SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('usuario_logado', jsonEncode(user));

      return user;
    } catch (e) {
      print('❌ [Auth] Erro ao fazer login: $e');
      return null;
    }
  }

  /// Sincronizar usuários da planilha para o banco local
  Future<bool> syncUsuarios() async {
    try {
      print('🔄 [Auth] Sincronizando usuários...');

      final result = await _userSync.syncUsuariosFromSheets();

      if (result.success) {
        print('✅ [Auth] Sincronização concluída: ${result.message}');
        return true;
      } else {
        print('❌ [Auth] Erro na sincronização: ${result.message}');
        return false;
      }
    } catch (e) {
      print('❌ [Auth] Erro ao sincronizar usuários: $e');
      return false;
    }
  }

  /// Verifica se existem usuários no banco local
  Future<bool> temUsuariosLocais() async {
    try {
      return await _userSync.temUsuariosLocais();
    } catch (e) {
      print('❌ [Auth] Erro ao verificar usuários locais: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getUsuarioLogado() async {
    if (_usuarioLogado != null) {
      return _usuarioLogado;
    }

    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('usuario_logado');

    if (userJson != null && userJson.isNotEmpty) {
      try {
        _usuarioLogado = jsonDecode(userJson);
        return _usuarioLogado;
      } catch (e) {
        print('⚠️ [Auth] Erro ao fazer parse do usuário: $e');
        // Remove dado corrompido
        await prefs.remove('usuario_logado');
        return null;
      }
    }

    return null;
  }

  bool isAdmin() {
    return _usuarioLogado?['perfil']?.toString().toUpperCase() == 'ADMIN';
  }

  Future<void> logout() async {
    _usuarioLogado = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('usuario_logado');
    print('👋 [Auth] Logout realizado');
  }

  Future<bool> isLoggedIn() async {
    final user = await getUsuarioLogado();
    return user != null;
  }
}
