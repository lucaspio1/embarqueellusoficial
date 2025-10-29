import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  // URL do Google Apps Script (mesma da planilha)
  final String _apiUrl = 'https://script.google.com/macros/s/AKfycbzLXa6c0HHv8Ff4uxvMNhvw8OB5gLzIhEv2uE4VPDGTCgZu6RsFIRPOv7I62VwZzBNk/exec';

  // Usuário logado em cache
  Map<String, dynamic>? _usuarioLogado;

  Future<Map<String, dynamic>?> login(String cpf, String senha) async {
    try {
      print('🔐 [Auth] Tentando login: CPF=$cpf');

      final request = http.Request('POST', Uri.parse(_apiUrl))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'action': 'login',
          'cpf': cpf,
          'senha': senha,
        });

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );

      var response = await http.Response.fromStream(streamedResponse);

      // Lidar com redirecionamento 302
      if (response.statusCode == 302) {
        final redirectUrl = response.headers['location'];
        if (redirectUrl != null) {
          print('🔄 [Auth] Redirecionando para: $redirectUrl');
          response = await http.get(Uri.parse(redirectUrl));
        }
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['user'] != null) {
          final user = data['user'];
          print('✅ [Auth] Login bem-sucedido: ${user['nome']} (${user['perfil']})');

          // Salvar usuário no cache
          _usuarioLogado = user;

          // Salvar no SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('usuario_logado', jsonEncode(user));

          return user;
        } else {
          print('❌ [Auth] Credenciais inválidas');
          return null;
        }
      } else {
        print('❌ [Auth] Erro HTTP: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ [Auth] Erro ao fazer login: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getUsuarioLogado() async {
    if (_usuarioLogado != null) {
      return _usuarioLogado;
    }

    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('usuario_logado');

    if (userJson != null) {
      _usuarioLogado = jsonDecode(userJson);
      return _usuarioLogado;
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
