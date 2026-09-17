import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Singleton pattern
  ApiService._privateConstructor();
  static final ApiService instance = ApiService._privateConstructor();

  String? _token;

  String get baseUrl {
    return dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';
  }

  bool get isAuthenticated => _token != null;
  String? get token => _token;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('jwt_token');
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
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

      if (response.statusCode == 401) {
        await logout();
        throw Exception('Sessão expirada');
      }

      return response;
    } catch (e) {
      print('❌ [API Error] $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> login(String cpf, String senha) async {
    final response = await _request('POST', '/api/mobile/auth', body: {
      'cpf': cpf,
      'senha': senha,
    });

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body);
      if (data['token'] != null) {
        _token = data['token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', _token!);
      }
      return data;
    } else {
      throw Exception(
          'Erro ao fazer login: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
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
