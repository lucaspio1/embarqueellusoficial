import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Singleton pattern
  ApiService._privateConstructor();
  static final ApiService instance = ApiService._privateConstructor();

  static const String _prefToken = 'jwt_token';
  static const String _prefRefresh = 'device_refresh_token';

  /// JWT de acesso (vence em 12h).
  String? _token;

  /// Token de dispositivo (vence após 30 dias SEM uso; cada renovação estende).
  /// Permite renovar o JWT sem senha depois de horas/dias offline.
  String? _refreshToken;

  /// Credenciais de um login OFFLINE, mantidas só em memória, para obter o
  /// token assim que a internet voltar (celular que nunca logou online).
  String? _cpfPendente;
  String? _senhaPendente;

  Future<bool>? _renovacaoEmAndamento;

  /// true quando o servidor recusou o token de dispositivo (revogado/vencido).
  /// A interface deve pedir um novo login COM internet.
  final ValueNotifier<bool> precisaNovoLogin = ValueNotifier<bool>(false);

  String get baseUrl {
    return dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';
  }

  /// true se o app tem algum meio de falar com a API: JWT válido, token de
  /// dispositivo ou credenciais de login offline aguardando internet.
  bool get isAuthenticated =>
      _token != null || _refreshToken != null || _senhaPendente != null;
  String? get token => _token;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_prefToken);
    _refreshToken = prefs.getString(_prefRefresh);
  }

  bool _ehRotaDeAutenticacao(String path) => path.startsWith('/api/mobile/auth');

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    bool tentouRenovar = false,
  }) async {
    // Sem JWT mas com como obtê-lo: renova antes de chamar
    var jaRenovou = tentouRenovar;
    if (!_ehRotaDeAutenticacao(path) && _token == null && !jaRenovou) {
      await renovarToken();
      jaRenovou = true;
    }

    var url = Uri.parse('$baseUrl$path');

    if (queryParams != null && queryParams.isNotEmpty) {
      url = url.replace(queryParameters: queryParams);
    }

    print('🌐 [API] $method $url');

    final headers = {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    http.Response response;
    try {
      if (method == 'GET') {
        response = await http
            .get(url, headers: headers)
            .timeout(const Duration(seconds: 30));
      } else if (method == 'POST') {
        response = await http
            .post(url, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 30));
      } else if (method == 'PUT') {
        response = await http
            .put(url, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 30));
      } else if (method == 'DELETE') {
        response = await http
            .delete(url, headers: headers)
            .timeout(const Duration(seconds: 30));
      } else {
        throw Exception('Método HTTP não suportado: $method');
      }

      if (response.statusCode == 401 && !_ehRotaDeAutenticacao(path)) {
        // JWT vencido: descarta só o JWT e tenta renovar uma vez.
        // NÃO desloga o usuário nem apaga a fila local.
        await _salvarToken(null);
        if (!jaRenovou && await renovarToken()) {
          return _request(method, path,
              body: body, queryParams: queryParams, tentouRenovar: true);
        }
        throw Exception('Sessão expirada');
      }

      return response;
    } catch (e) {
      print('❌ [API Error] $e');
      rethrow;
    }
  }

  /// Obtém um novo JWT usando o token de dispositivo ou, na falta dele, as
  /// credenciais de um login offline. Retorna true se conseguiu.
  /// Falha de rede mantém tudo como está (tenta de novo no próximo ciclo).
  Future<bool> renovarToken() {
    return _renovacaoEmAndamento ??= _renovar().whenComplete(() {
      _renovacaoEmAndamento = null;
    });
  }

  Future<bool> _renovar() async {
    try {
      if (_refreshToken != null) {
        final response = await http
            .post(
              Uri.parse('$baseUrl/api/mobile/auth/refresh'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'refresh_token': _refreshToken}),
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body);
          if (data['token'] != null) {
            await _salvarToken(data['token'] as String);
            precisaNovoLogin.value = false;
            print('🔑 [API] JWT renovado com token de dispositivo');
            return true;
          }
        }
        if (response.statusCode == 401) {
          // Revogado, vencido ou usuário desativado: só um login online resolve
          print('🔒 [API] Token de dispositivo recusado: ${response.body}');
          await _salvarRefreshToken(null);
          if (_senhaPendente == null) precisaNovoLogin.value = true;
        } else {
          return false; // erro de servidor/rede: tenta no próximo ciclo
        }
      }

      if (_cpfPendente != null && _senhaPendente != null) {
        final data = await login(_cpfPendente!, _senhaPendente!);
        return data['token'] != null;
      }
      return false;
    } catch (e) {
      print('⚠️ [API] Não foi possível renovar o token agora: $e');
      return false;
    }
  }

  Future<void> _salvarToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_prefToken);
    } else {
      await prefs.setString(_prefToken, token);
    }
  }

  Future<void> _salvarRefreshToken(String? refresh) async {
    _refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    if (refresh == null) {
      await prefs.remove(_prefRefresh);
    } else {
      await prefs.setString(_prefRefresh, refresh);
    }
  }

  /// Login OFFLINE bem-sucedido: guarda as credenciais só em memória para
  /// obter o token quando a internet voltar.
  void definirCredenciaisPendentes(String cpf, String senha) {
    _cpfPendente = cpf;
    _senhaPendente = senha;
  }

  Future<Map<String, dynamic>> login(String cpf, String senha) async {
    final response = await _request('POST', '/api/mobile/auth', body: {
      'cpf': cpf,
      'senha': senha,
    });

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body);
      if (data['token'] != null) {
        await _salvarToken(data['token'] as String);
        if (data['refresh_token'] != null) {
          await _salvarRefreshToken(data['refresh_token'] as String);
        }
        _cpfPendente = null;
        _senhaPendente = null;
        precisaNovoLogin.value = false;
      }
      return data;
    } else {
      if (response.statusCode == 401) {
        // Senha mudou ou usuário removido: não insistir com essas credenciais
        _cpfPendente = null;
        _senhaPendente = null;
      }
      throw Exception(
          'Erro ao fazer login: ${response.statusCode} - ${response.body}');
    }
  }

  /// Logout do monitor. Mantém o token de dispositivo para que a fila local
  /// (embarques, logs, faciais) continue subindo mesmo após o logout; o
  /// próximo login online o substitui.
  Future<void> logout() async {
    _cpfPendente = null;
    _senhaPendente = null;
    await _salvarToken(null);
  }

  Future<Map<String, dynamic>> syncDelta(String? lastSyncTime) async {
    final queryParams = <String, String>{};
    if (lastSyncTime != null) {
      queryParams['since'] = lastSyncTime;
    }
    
    final response = await _request('GET', '/api/mobile/sync', queryParams: queryParams);
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Erro em syncDelta: ${response.statusCode} - ${response.body}');
    }
  }

  Future<Map<String, dynamic>> uploadBatch(
      List<Map<String, dynamic>> operations) async {
    final response = await _request('POST', '/api/mobile/sync/upload', body: {
      'operations': operations,
    });
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Erro em uploadBatch: ${response.statusCode} - ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getAlunosPorViagem({
    String? colegio,
    String? inicio,
  }) async {
    final queryParams = <String, String>{};
    if (colegio != null) queryParams['colegio'] = colegio;
    if (inicio != null) queryParams['inicio'] = inicio;

    final response = await _request('GET', '/api/mobile/alunos', queryParams: queryParams);
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Erro ao buscar alunos: ${response.statusCode} - ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getEmbarquesPorViagem({
    String? colegio,
    String? inicio,
    String? idPasseio,
    String? onibus,
  }) async {
    final queryParams = <String, String>{};
    if (colegio != null) queryParams['colegio'] = colegio;
    if (inicio != null) queryParams['inicio'] = inicio;
    if (idPasseio != null) queryParams['idPasseio'] = idPasseio;
    if (onibus != null) queryParams['onibus'] = onibus;

    final response = await _request('GET', '/api/mobile/embarques', queryParams: queryParams);
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Erro ao buscar embarques: ${response.statusCode} - ${response.body}');
    }
  }

  Future<Map<String, dynamic>> registrarMovimentacao({
    required String cpf,
    required String novaLocalizacao,
    String? nome,
    String? quarto,
    String? operador,
  }) async {
    final response = await _request('POST', '/api/movimentar', body: {
      'cpf': cpf,
      'novaLocalizacao': novaLocalizacao,
      if (nome != null) 'nome': nome,
      if (quarto != null) 'quarto': quarto,
      if (operador != null) 'operador': operador,
    });
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Erro ao registrar movimentação: ${response.statusCode} - ${response.body}');
    }
  }

  Future<Map<String, dynamic>> registrarEmbarque({
    required String cpf,
    required String campo,
    required String valor,
  }) async {
    final operation = {
      'type': 'embarque',
      'cpf': cpf,
      'campo': campo,
      'valor': valor,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    return await uploadBatch([operation]);
  }
}
