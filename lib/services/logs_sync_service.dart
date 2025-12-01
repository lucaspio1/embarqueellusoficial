// lib/services/logs_sync_service.dart — FACADE
// Mantém compatibilidade com código existente, mas agora usa Firebase
import 'package:sqflite/sqflite.dart' as Sqflite;
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/user_sync_service.dart';

/// Facade para sincronização de logs
/// Agora os dados vêm automaticamente do Firebase via listeners em tempo real
class LogsSyncService {
  static final LogsSyncService instance = LogsSyncService._internal();
  LogsSyncService._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Sincroniza LOGS do Firebase
  /// Nota: A sincronização é automática via listeners, este método existe para compatibilidade
  Future<SyncResult> syncLogsFromSheets() async {
    print('ℹ️ [LogsSyncService] Sincronização automática de logs via Firebase listeners');

    final db = await _db.database;
    final countResult = await db.rawQuery('SELECT COUNT(*) FROM logs');
    final count = Sqflite.firstIntValue(countResult) ?? 0;

    return SyncResult(
      success: true,
      message: 'Sincronização automática ativa',
      itemsProcessed: count,
    );
  }

  /// Verifica se há logs locais
  Future<bool> temLogsLocais() async {
    final db = await _db.database;
    final countResult = await db.rawQuery('SELECT COUNT(*) FROM logs');
    final count = Sqflite.firstIntValue(countResult) ?? 0;
    return count > 0;
  }
}
