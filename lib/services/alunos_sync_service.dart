// lib/services/alunos_sync_service.dart — FACADE
// Mantém compatibilidade com código existente, mas agora usa Firebase
import 'package:sqflite/sqflite.dart' as Sqflite;
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/user_sync_service.dart';

/// Facade para sincronização de alunos e pessoas
/// Agora os dados vêm automaticamente do Firebase via listeners em tempo real
class AlunosSyncService {
  static final AlunosSyncService instance = AlunosSyncService._internal();
  AlunosSyncService._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Sincroniza PESSOAS do Firebase
  /// Nota: A sincronização é automática via listeners, este método existe para compatibilidade
  Future<SyncResult> syncPessoasFromSheets() async {
    print('ℹ️ [AlunosSyncService] Sincronização automática de pessoas via Firebase listeners');

    final db = await _db.database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM pessoas_facial');
    final count = (countResult.first['count'] as int?) ?? 0;

    return SyncResult(
      success: true,
      message: 'Sincronização automática ativa',
      itemsProcessed: count,
    );
  }

  /// Sincroniza ALUNOS do Firebase
  /// Nota: A sincronização é automática via listeners, este método existe para compatibilidade
  Future<SyncResult> syncAlunosFromSheets() async {
    print('ℹ️ [AlunosSyncService] Sincronização automática de alunos via Firebase listeners');

    final db = await _db.database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM alunos');
    final count = (countResult.first['count'] as int?) ?? 0;

    return SyncResult(
      success: true,
      message: 'Sincronização automática ativa',
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
