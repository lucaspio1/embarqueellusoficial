// lib/services/quartos_sync_service.dart — FACADE
// Mantém compatibilidade com código existente, mas agora usa Firebase
import 'package:sqflite/sqflite.dart' as Sqflite;
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/user_sync_service.dart';

class QuartosSyncService {
  static final QuartosSyncService instance = QuartosSyncService._internal();
  QuartosSyncService._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Sincroniza quartos do Firebase
  /// Nota: A sincronização é automática via listeners, este método existe para compatibilidade
  Future<SyncResult> syncQuartosFromSheets() async {
    print('ℹ️ [QuartosSyncService] Sincronização automática de quartos via Firebase listeners');

    final db = await _db.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM quartos')
    ) ?? 0;

    return SyncResult(
      success: true,
      message: 'Sincronização automática ativa',
      itemsProcessed: count,
      count: count,
    );
  }

  /// Verifica se há quartos locais
  Future<bool> temQuartosLocais() async {
    final quartos = await _db.getAllQuartos();
    return quartos.isNotEmpty;
  }
}
