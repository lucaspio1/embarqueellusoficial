// lib/services/auth_service.dart
// Serviço de autenticação — agora usa JWT via API REST do backend Node.js
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/api_service.dart';
import 'package:embarqueellus/services/user_sync_service.dart';

class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  final _db = DatabaseHelper.instance;
  final _userSync = UserSyncService.instance;
  final _api = ApiService.instance;

  // Usuário logado em cache
  Map<String, dynamic>? _usuarioLogado;

  /// Login — tenta via API REST primeiro, depois fallback SQLite (offline)
  Future<Map<String, dynamic>?> login(String cpf, String senha) async {
    try {
      print('🔐 [Auth] Tentando login: CPF=$cpf');

      // Garantir que a tabela de usuários existe
      await _db.ensureFacialSchema();

      // PASSO 1: Tentar login online via API REST
      try {
        final response = await _api.login(cpf, senha);
        if (response['success'] == true && response['user'] != null) {
          final user = {
            'id': response['user']['cpf']?.toString() ?? cpf,
            'nome': response['user']['nome'],
            'cpf': response['user']['cpf']?.toString() ?? cpf,
            'perfil': response['user']['perfil'] ?? 'USER',
          };

          print('✅ [Auth] Login online bem-sucedido: ${user['nome']} (${user['perfil']})');

          // Salvar usuário no cache e no banco local (para login offline futuro)
          _usuarioLogado = user;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('usuario_logado', jsonEncode(user));

          // Salvar usuário no SQLite para fallback offline
          try {
            await _db.upsertUsuario({
              'cpf': user['cpf'],
              'nome': user['nome'],
              'senha_hash': senha, // O backend já faz bcrypt; aqui é para fallback
              'perfil': user['perfil'],
              'ativo': 1,
            });
          } catch (_) {}

          return user;
        }
      } catch (e) {
        print('⚠️ [Auth] Login online falhou ($e), tentando offline...');
      }

      // PASSO 2: Fallback offline — buscar no banco local
      final usuario = await _db.getUsuarioByCpf(cpf);

      if (usuario == null) {
        print('❌ [Auth] Usuário não encontrado (online e offline)');
        return null;
      }

      // Verificar senha localmente
      final senhaValida = _userSync.verificarSenha(senha, usuario['senha_hash']);

      if (!senhaValida) {
        print('❌ [Auth] Senha inválida (offline)');
        return null;
      }

      // Login offline bem-sucedido
      final user = {
        'id': usuario['user_id']?.toString() ?? usuario['id'].toString(),
        'nome': usuario['nome'],
        'cpf': usuario['cpf'],
        'perfil': usuario['perfil'] ?? 'USUARIO',
      };

      print('✅ [Auth] Login OFFLINE bem-sucedido: ${user['nome']} (${user['perfil']})');

      _usuarioLogado = user;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('usuario_logado', jsonEncode(user));

      return user;
    } catch (e) {
      print('❌ [Auth] Erro ao fazer login: $e');
      return null;
    }
  }

  /// Sincronizar usuários (mantido para compatibilidade)
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
    await _api.logout(); // Limpa JWT
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('usuario_logado');
    print('👋 [Auth] Logout realizado');
  }

  Future<bool> isLoggedIn() async {
    final user = await getUsuarioLogado();
    return user != null;
  }
}
