// lib/config/app_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Classe de configuração centralizada do aplicativo
/// Lê todas as configurações do arquivo .env
class AppConfig {
  // Singleton
  AppConfig._();
  static final AppConfig instance = AppConfig._();

  /// ⚠️ DEPRECATED: URL do Google Apps Script - DADOS GERAIS (ALUNOS, PESSOAS, LOGS, LOGIN)
  ///
  /// **Firebase é agora a fonte principal de dados.**
  /// Esta configuração é mantida apenas para compatibilidade com código legado (outbox sync).
  /// Novos dados vêm automaticamente do Firebase via listeners em tempo real.
  @Deprecated('Use Firebase como fonte de dados. Mantido apenas para outbox sync legado.')
  String get googleAppsScriptUrl {
    return dotenv.get(
      'GOOGLE_APPS_SCRIPT_URL',
      fallback: '',
    );
  }

  /// ⚠️ DEPRECATED: URL do Google Apps Script - EMBARQUES/PASSEIOS
  ///
  /// **Firebase é agora a fonte principal de dados.**
  /// Esta configuração é mantida apenas para compatibilidade com código legado.
  @Deprecated('Use Firebase como fonte de dados.')
  String get embarqueScriptUrl {
    return dotenv.get(
      'EMBARQUE_SCRIPT_URL',
      fallback: '',
    );
  }

  /// ⚠️ DEPRECATED: ID da Planilha do Google Sheets
  ///
  /// **Firebase é agora a fonte principal de dados.**
  /// Esta configuração é mantida apenas para compatibilidade com código legado.
  @Deprecated('Use Firebase como fonte de dados.')
  String get spreadsheetId {
    return dotenv.get(
      'SPREADSHEET_ID',
      fallback: '1xl2wJdaqzIkTA3gjBQws5j6XrOw3AR5RC7_CrDR1M0U',
    );
  }

  /// Intervalo de sincronização em minutos
  int get syncIntervalMinutes {
    return int.tryParse(
      dotenv.get('SYNC_INTERVAL_MINUTES', fallback: '1'),
    ) ?? 1;
  }

  /// Número máximo de tentativas de retry
  int get maxRetryAttempts {
    return int.tryParse(
      dotenv.get('MAX_RETRY_ATTEMPTS', fallback: '3'),
    ) ?? 3;
  }

  /// Threshold de confiança para reconhecimento facial
  double get faceConfidenceThreshold {
    return double.tryParse(
      dotenv.get('FACE_CONFIDENCE_THRESHOLD', fallback: '0.7'),
    ) ?? 0.7;
  }

  /// Tamanho do embedding facial
  int get embeddingSize {
    return int.tryParse(
      dotenv.get('EMBEDDING_SIZE', fallback: '512'),
    ) ?? 512;
  }

  /// Timeout para requisições API em segundos
  int get apiTimeoutSeconds {
    return int.tryParse(
      dotenv.get('API_TIMEOUT_SECONDS', fallback: '30'),
    ) ?? 30;
  }

  /// URL base da API REST do backend Node.js (Cloud Run)
  String get apiBaseUrl {
    return dotenv.get('API_BASE_URL', fallback: 'http://localhost:3000');
  }

  /// Valida se todas as configurações obrigatórias foram fornecidas
  bool get isValid {
    if (googleAppsScriptUrl.isEmpty) {
      print('❌ [Config] GOOGLE_APPS_SCRIPT_URL não configurada no .env');
      return false;
    }
    if (embarqueScriptUrl.isEmpty) {
      print('❌ [Config] EMBARQUE_SCRIPT_URL não configurada no .env');
      return false;
    }
    if (spreadsheetId.isEmpty) {
      print('❌ [Config] SPREADSHEET_ID não configurada no .env');
      return false;
    }
    return true;
  }

  /// Imprime as configurações atuais (sem expor valores sensíveis)
  void printConfig() {
    print('📋 [Config] Configurações carregadas:');
    print('   - API Base URL: $apiBaseUrl');
    print('   - Google Apps Script URL (Dados): ${googleAppsScriptUrl.isNotEmpty ? "✓ Configurada" : "✗ Não configurada"}');
    print('   - Embarque Script URL (Passeios): ${embarqueScriptUrl.isNotEmpty ? "✓ Configurada" : "✗ Não configurada"}');
    print('   - Spreadsheet ID: ${spreadsheetId.isNotEmpty ? "✓ Configurada" : "✗ Não configurada"}');
    print('   - Intervalo de Sync: $syncIntervalMinutes minuto(s)');
    print('   - Max Retry: $maxRetryAttempts tentativa(s)');
    print('   - Face Confidence: $faceConfidenceThreshold');
    print('   - Embedding Size: $embeddingSize');
    print('   - API Timeout: $apiTimeoutSeconds segundos');
  }
}
