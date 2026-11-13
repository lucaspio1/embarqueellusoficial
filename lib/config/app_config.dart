// lib/config/app_config.dart
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Classe de configuração centralizada do aplicativo.
/// Combina configurações estáticas (.env) com configurações remotas recebidas
/// do Painel Web via `/api/mobile/sync`, persistidas localmente (offline-first).
class AppConfig {
  AppConfig._();
  static final AppConfig instance = AppConfig._();

  static const String _prefRemoteConfigKey = 'remote_app_config_v1';

  /// Versão atual instalada do aplicativo (sincronizada com pubspec.yaml)
  static const String currentAppVersion = String.fromEnvironment(
    'FLUTTER_BUILD_NAME',
    defaultValue: '5.2.1',
  );

  /// Notificador disparado sempre que a configuração remota é atualizada
  final ValueNotifier<int> configVersion = ValueNotifier<int>(0);

  Map<String, dynamic> _remote = {};
  bool _updateDismissedInSession = false;

  /// Inicializa carregando a última configuração remota salva no dispositivo
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefRemoteConfigKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _remote = decoded;
          configVersion.value++;
        }
      }
    } catch (e) {
      print('⚠️ [AppConfig] Erro ao carregar configuração remota local: $e');
    }
  }

  /// Aplica e persiste as configurações recebidas do servidor no sync delta
  Future<bool> applyRemoteConfig(Map<String, dynamic> newConfig) async {
    try {
      final prevInterval = syncIntervalSeconds;
      _remote = Map<String, dynamic>.from(newConfig);
      configVersion.value++;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefRemoteConfigKey, jsonEncode(_remote));
      return prevInterval != syncIntervalSeconds;
    } catch (e) {
      print('⚠️ [AppConfig] Erro ao salvar configuração remota: $e');
      return false;
    }
  }

  double _clampDouble(dynamic val, double min, double max, double fallback) {
    if (val == null) return fallback;
    final num? parsed = val is num ? val : double.tryParse(val.toString());
    if (parsed == null || parsed.isNaN) return fallback;
    return parsed.toDouble().clamp(min, max);
  }

  int _clampInt(dynamic val, int min, int max, int fallback) {
    if (val == null) return fallback;
    final num? parsed = val is num ? val : num.tryParse(val.toString());
    if (parsed == null || parsed.isNaN) return fallback;
    return parsed.round().clamp(min, max);
  }

  bool _toBool(dynamic val, bool fallback) {
    if (val is bool) return val;
    if (val == 'true' || val == 1 || val == '1') return true;
    if (val == 'false' || val == 0 || val == '0') return false;
    return fallback;
  }

  // =========================================================================
  // PARÂMETROS REMOTOS — RECONHECIMENTO FACIAL & CÂMERA
  // =========================================================================

  /// Limiar de distância L2 para considerar um rosto reconhecido (padrão: 0.95)
  double get distanceThreshold =>
      _clampDouble(_remote['distance_threshold'], 0.50, 1.40, 0.95);

  /// Quantidade de fotos disparadas em rajada no cadastro com 1 toque (padrão: 3)
  int get enrollmentBurstCount =>
      _clampInt(_remote['enrollment_burst_count'], 1, 5, 3);

  /// Intervalo em ms entre cada foto da rajada (padrão: 350 ms)
  int get enrollmentBurstIntervalMs =>
      _clampInt(_remote['enrollment_burst_interval_ms'], 150, 1500, 350);

  /// Validade do cache de embeddings em memória em minutos (padrão: 5 min)
  int get faceCacheTtlMinutes =>
      _clampInt(_remote['face_cache_ttl_minutes'], 1, 60, 5);

  /// Tamanho mínimo da face para o ML Kit nativo (padrão: 0.05)
  double get mlkitMinFaceSize =>
      _clampDouble(_remote['mlkit_min_face_size'], 0.01, 0.30, 0.05);

  /// Qualidade JPEG do recorte facial 112x112 (padrão: 95)
  int get jpegQuality => _clampInt(_remote['jpeg_quality'], 60, 100, 95);

  /// Resolução da câmera configurada remotamente (padrão: ResolutionPreset.high)
  ResolutionPreset get cameraResolutionPreset {
    final res = (_remote['camera_resolution'] ?? 'high').toString().trim();
    switch (res) {
      case 'medium':
        return ResolutionPreset.medium;
      case 'veryHigh':
        return ResolutionPreset.veryHigh;
      case 'high':
      default:
        return ResolutionPreset.high;
    }
  }

  bool get useFrontCameraRecognition =>
      _toBool(_remote['use_front_camera_recognition'], false);

  bool get useFrontCameraEnrollment =>
      _toBool(_remote['use_front_camera_enrollment'], false);

  bool get showFaceGuide => _toBool(_remote['show_face_guide'], true);

  // =========================================================================
  // PARÂMETROS REMOTOS — SINCRONIZAÇÃO, REDE & QR CODE
  // =========================================================================

  /// Intervalo de sincronização em segundos (padrão: 60s)
  int get syncIntervalSeconds =>
      _clampInt(_remote['sync_interval_seconds'], 15, 600, 60);

  /// Timeout para requisições API em segundos (padrão: 30s)
  int get apiTimeoutSeconds {
    final envDefault =
        int.tryParse(dotenv.get('API_TIMEOUT_SECONDS', fallback: '30')) ?? 30;
    return _clampInt(_remote['api_timeout_seconds'], 10, 120, envDefault);
  }

  /// Tamanho máximo do lote da fila offline por rodada (padrão: 50)
  int get syncBatchSize => _clampInt(_remote['sync_batch_size'], 10, 200, 50);

  /// Cooldown entre leituras seguidas de QR Code em segundos (padrão: 2s)
  int get qrCooldownSeconds =>
      _clampInt(_remote['qr_cooldown_seconds'], 1, 10, 2);

  // =========================================================================
  // PARÂMETROS REMOTOS — SENTRY & LEMBRETE DE ATUALIZAÇÃO (NÃO BLOQUEANTE)
  // =========================================================================

  bool get sentryFacialVerboseLogs =>
      _toBool(_remote['sentry_facial_verbose_logs'], false);

  double get sentryTracesSampleRate =>
      _clampDouble(_remote['sentry_traces_sample_rate'], 0.0, 1.0, 0.2);

  String get recommendedVersion =>
      (_remote['recommended_version'] ?? currentAppVersion).toString().trim();

  String get updateMessage {
    final msg = (_remote['update_message'] ?? '').toString().trim();
    if (msg.isNotEmpty) return msg;
    return 'Há uma nova versão ($recommendedVersion) do aplicativo disponível. Atualize quando estiver no Wi-Fi.';
  }

  String get storeUrlAndroid =>
      (_remote['store_url_android'] ?? '').toString().trim();

  String get storeUrlIos => (_remote['store_url_ios'] ?? '').toString().trim();

  /// Retorna true se `recommendedVersion` for maior que `currentAppVersion`
  bool get isUpdateAvailable =>
      _compareSemver(currentAppVersion, recommendedVersion) < 0;

  /// Retorna true se houver atualização recomendada e o monitor ainda não tiver
  /// dispensado o aviso nesta sessão (NUNCA bloqueia o uso do app).
  bool get shouldShowUpdateReminder =>
      isUpdateAvailable && !_updateDismissedInSession;

  /// Dispensa o lembrete de atualização durante a sessão atual
  void dismissUpdateReminderForSession() {
    _updateDismissedInSession = true;
    configVersion.value++;
  }

  int _compareSemver(String a, String b) {
    final cleanA = a.split('+').first.trim();
    final cleanB = b.split('+').first.trim();
    final partsA = cleanA.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final partsB = cleanB.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  // =========================================================================
  // CONFIGURAÇÕES LEGADAS / .ENV
  // =========================================================================

  @Deprecated('Use Firebase como fonte de dados. Mantido apenas para outbox sync legado.')
  String get googleAppsScriptUrl =>
      dotenv.get('GOOGLE_APPS_SCRIPT_URL', fallback: '');

  @Deprecated('Use Firebase como fonte de dados.')
  String get embarqueScriptUrl =>
      dotenv.get('EMBARQUE_SCRIPT_URL', fallback: '');

  @Deprecated('Use Firebase como fonte de dados.')
  String get spreadsheetId => dotenv.get(
        'SPREADSHEET_ID',
        fallback: '1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U',
      );

  int get syncIntervalMinutes =>
      int.tryParse(dotenv.get('SYNC_INTERVAL_MINUTES', fallback: '1')) ?? 1;

  int get maxRetryAttempts =>
      int.tryParse(dotenv.get('MAX_RETRY_ATTEMPTS', fallback: '3')) ?? 3;

  double get faceConfidenceThreshold =>
      double.tryParse(dotenv.get('FACE_CONFIDENCE_THRESHOLD', fallback: '0.7')) ??
      0.7;

  int get embeddingSize =>
      int.tryParse(dotenv.get('EMBEDDING_SIZE', fallback: '512')) ?? 512;

  String get apiBaseUrl =>
      dotenv.get('API_BASE_URL', fallback: 'http://localhost:3000');

  bool get isValid =>
      googleAppsScriptUrl.isNotEmpty &&
      embarqueScriptUrl.isNotEmpty &&
      spreadsheetId.isNotEmpty;

  void printConfig() {
    print('📋 [Config] Configurações carregadas:');
    print('   - Versão do App: $currentAppVersion (recomendada: $recommendedVersion)');
    print('   - API Base URL: $apiBaseUrl');
    print('   - Distance Threshold: $distanceThreshold');
    print('   - Rajada Cadastro: $enrollmentBurstCount fotos (${enrollmentBurstIntervalMs}ms)');
    print('   - Intervalo de Sync: ${syncIntervalSeconds}s');
    print('   - API Timeout: ${apiTimeoutSeconds}s');
  }
}
