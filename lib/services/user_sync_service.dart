// lib/services/user_sync_service.dart — FACADE
// Mantém compatibilidade com código existente, mas agora usa Firebase
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart' as Sqflite;
import 'package:embarqueellus/database/database_helper.dart';

/// Facade para sincronização de usuários
/// Agora os dados vêm automaticamente do Firebase via listeners em tempo real
class UserSyncService {
  static final UserSyncService instance = UserSyncService._internal();
  UserSyncService._internal();

  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Sincroniza usuários do Firebase
  /// Nota: A sincronização é automática via listeners, este método existe para compatibilidade
  Future<SyncResult> syncUsuariosFromSheets() async {
    print('ℹ️ [UserSyncService] Sincronização automática via Firebase listeners');

    // Retorna resultado dummy para manter compatibilidade
    final db = await _db.database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM usuarios');
    final count = (countResult.first['count'] as int?) ?? 0;

    return SyncResult(
      success: true,
      message: 'Sincronização automática ativa',
      itemsProcessed: count,
    );
  }

  /// Verifica senha (aceita texto plano ou hash SHA-256)
  bool verificarSenha(String senha, String senhaArmazenada) {
    // Primeiro tenta comparação direta (texto plano)
    if (senha == senhaArmazenada) {
      return true;
    }

    // Se não der match, tenta com hash SHA-256 (para compatibilidade)
    final bytes = utf8.encode(senha);
    final hash = sha256.convert(bytes).toString();
    return hash == senhaArmazenada;
  }

  /// Verifica se há usuários locais
  Future<bool> temUsuariosLocais() async {
    final db = await _db.database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM usuarios WHERE ativo = 1');
    final count = (countResult.first['count'] as int?) ?? 0;
    return count > 0;
  }
}

/// Classe de resultado de sincronização
class SyncResult {
  final bool success;
  final String message;
  final int itemsProcessed;

  SyncResult({
    required this.success,
    required this.message,
    required this.itemsProcessed,
  });
}
