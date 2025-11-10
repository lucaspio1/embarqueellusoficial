// lib/services/user_sync_service.dart — FACADE (FASE 1)
// Mantém compatibilidade com código existente, mas delega para OfflineSyncService
import 'package:embarqueellus/services/offline_sync_service.dart';

/// Facade para sincronização de usuários
/// Mantém interface pública mas delega para OfflineSyncService
class UserSyncService {
  static final UserSyncService instance = UserSyncService._internal();
  UserSyncService._internal();

  final _offlineSync = OfflineSyncService.instance;

  /// Sincroniza usuários do Google Sheets
  /// Delega para OfflineSyncService._syncUsers()
  Future<SyncResult> syncUsuariosFromSheets() async {
    print('🔄 [UserSyncService] Delegando para OfflineSyncService...');
    return await _offlineSync.syncAll().then((result) {
      print('✅ [UserSyncService] Sincronização completa: ${result.users}');
      return result.users;
    });
  }

  /// Verifica senha (delegado para OfflineSyncService)
  bool verificarSenha(String senha, String senhaHash) {
    return _offlineSync.verificarSenha(senha, senhaHash);
  }

  /// Verifica se há usuários locais (delegado para OfflineSyncService)
  Future<bool> temUsuariosLocais() async {
    return await _offlineSync.temUsuariosLocais();
  }
}
