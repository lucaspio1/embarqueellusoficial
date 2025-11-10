// lib/services/logs_sync_service.dart — FACADE (FASE 1)
// Mantém compatibilidade com código existente, mas delega para OfflineSyncService
import 'package:embarqueellus/services/offline_sync_service.dart';

/// Facade para sincronização de logs
/// Mantém interface pública mas delega para OfflineSyncService
class LogsSyncService {
  static final LogsSyncService instance = LogsSyncService._internal();
  LogsSyncService._internal();

  final _offlineSync = OfflineSyncService.instance;

  /// Sincroniza LOGS da aba LOGS do Google Sheets
  /// Delega para OfflineSyncService._syncLogs()
  Future<SyncResult> syncLogsFromSheets() async {
    print('🔄 [LogsSyncService] Delegando sincronização de logs...');
    return await _offlineSync.syncAll().then((result) {
      print('✅ [LogsSyncService] Logs sincronizados: ${result.logs}');
      return result.logs;
    });
  }

  /// Verifica se há logs locais (delegado para OfflineSyncService)
  Future<bool> temLogsLocais() async {
    return await _offlineSync.temLogsLocais();
  }
}
