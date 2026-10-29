// lib/services/alunos_sync_service.dart — FACADE
// Mantém compatibilidade com código existente, delegando para FirebaseService (REST API)
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/firebase_service.dart';
import 'package:embarqueellus/services/user_sync_service.dart';

/// Facade para sincronização de alunos e pessoas
class AlunosSyncService {
  static final AlunosSyncService instance = AlunosSyncService._internal();
  AlunosSyncService._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Sincroniza PESSOAS via backend REST
  Future<SyncResult> syncPessoasFromSheets() async {
    await FirebaseService.instance.trySyncInBackground();

    final db = await _db.database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM alunos WHERE facial_cadastrada = 1');
    final count = (countResult.first['count'] as int?) ?? 0;

    return SyncResult(
      success: true,
      message: '$count pessoa(s) com facial sincronizada(s)',
      itemsProcessed: count,
    );
  }

  /// Sincroniza ALUNOS via backend REST
  Future<SyncResult> syncAlunosFromSheets() async {
    await FirebaseService.instance.trySyncInBackground();

    final db = await _db.database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM alunos');
    final count = (countResult.first['count'] as int?) ?? 0;

    return SyncResult(
      success: true,
      message: '$count aluno(s) sincronizado(s)',
      itemsProcessed: count,
    );
  }

  /// Verifica se há alunos locais
  Future<bool> temAlunosLocais() async {
    final db = await _db.database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM alunos');
    final count = (countResult.first['count'] as int?) ?? 0;
    return count > 0;
  }
}
