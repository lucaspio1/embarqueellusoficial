// lib/services/alunos_sync_service.dart — FACADE (FASE 1)
// Mantém compatibilidade com código existente, mas delega para OfflineSyncService
import 'package:embarqueellus/services/offline_sync_service.dart';

/// Facade para sincronização de alunos e pessoas
/// Mantém interface pública mas delega para OfflineSyncService
class AlunosSyncService {
  static final AlunosSyncService instance = AlunosSyncService._internal();
  AlunosSyncService._internal();

  final _offlineSync = OfflineSyncService.instance;

  /// Sincroniza PESSOAS da aba PESSOAS do Google Sheets (com embeddings)
  /// Delega para OfflineSyncService._syncPessoas()
  Future<SyncResult> syncPessoasFromSheets() async {
    print('🔄 [AlunosSyncService] Delegando sincronização de pessoas...');
    return await _offlineSync.syncAll().then((result) {
      print('✅ [AlunosSyncService] Pessoas sincronizadas: ${result.pessoas}');
      return result.pessoas;
    });
  }

  /// Sincroniza ALUNOS da aba ALUNOS do Google Sheets
  /// Delega para OfflineSyncService._syncAlunos()
  Future<SyncResult> syncAlunosFromSheets() async {
    print('🔄 [AlunosSyncService] Delegando sincronização de alunos...');
    return await _offlineSync.syncAll().then((result) {
      print('✅ [AlunosSyncService] Alunos sincronizados: ${result.alunos}');
      return result.alunos;
    });
  }

  /// Verifica se há alunos locais (delegado para OfflineSyncService)
  Future<bool> temAlunosLocais() async {
    return await _offlineSync.temAlunosLocais();
  }
}
