// lib/services/sync_manager.dart
// Gerenciador de estado de sincronização com Safety Buffer
import 'package:shared_preferences/shared_preferences.dart';

/// Gerencia timestamps de sincronização com margem de segurança (Safety Buffer)
///
/// O Safety Buffer garante que nenhum dado seja perdido em caso de:
/// - Diferenças de relógio entre cliente e servidor
/// - Latência de rede
/// - Operações que acontecem exatamente no momento da sync
///
/// Exemplo: Se a última sync foi às 10:00, o próximo since será 09:40 (20min antes)
class SyncManager {
  SyncManager._();
  static final SyncManager instance = SyncManager._();

  // Duração do buffer de segurança (20 minutos)
  static const Duration _safetyBuffer = Duration(minutes: 20);

  // Chaves para SharedPreferences
  static const String _keyLastSyncUsers = 'last_sync_users';
  static const String _keyLastSyncPeople = 'last_sync_people';
  static const String _keyLastSyncStudents = 'last_sync_students';
  static const String _keyLastSyncLogs = 'last_sync_logs';
  static const String _keyLastSyncQuartos = 'last_sync_quartos';
  static const String _keyLastSyncEventos = 'last_sync_eventos';

  /// Retorna o timestamp da última sincronização de usuários
  Future<String?> getLastSyncUsers() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSyncUsers);
  }

  /// Retorna o timestamp da última sincronização de pessoas
  Future<String?> getLastSyncPeople() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSyncPeople);
  }

  /// Retorna o timestamp da última sincronização de alunos
  Future<String?> getLastSyncStudents() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSyncStudents);
  }

  /// Retorna o timestamp da última sincronização de logs
  Future<String?> getLastSyncLogs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSyncLogs);
  }

  /// Retorna o timestamp da última sincronização de quartos
  Future<String?> getLastSyncQuartos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSyncQuartos);
  }

  /// Retorna o timestamp da última sincronização de eventos
  Future<String?> getLastSyncEventos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSyncEventos);
  }

  /// Salva timestamp de sincronização de usuários (vindo do servidor)
  Future<void> saveServerSyncTimeUsers(String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSyncUsers, timestamp);
    print('💾 [SyncManager] Timestamp de users salvo: $timestamp');
  }

  /// Salva timestamp de sincronização de pessoas (vindo do servidor)
  Future<void> saveServerSyncTimePeople(String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSyncPeople, timestamp);
    print('💾 [SyncManager] Timestamp de people salvo: $timestamp');
  }

  /// Salva timestamp de sincronização de alunos (vindo do servidor)
  Future<void> saveServerSyncTimeStudents(String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSyncStudents, timestamp);
    print('💾 [SyncManager] Timestamp de students salvo: $timestamp');
  }

  /// Salva timestamp de sincronização de logs (vindo do servidor)
  Future<void> saveServerSyncTimeLogs(String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSyncLogs, timestamp);
    print('💾 [SyncManager] Timestamp de logs salvo: $timestamp');
  }

  /// Salva timestamp de sincronização de quartos (vindo do servidor)
  Future<void> saveServerSyncTimeQuartos(String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSyncQuartos, timestamp);
    print('💾 [SyncManager] Timestamp de quartos salvo: $timestamp');
  }

  /// Salva timestamp de sincronização de eventos (vindo do servidor)
  Future<void> saveServerSyncTimeEventos(String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSyncEventos, timestamp);
    print('💾 [SyncManager] Timestamp de eventos salvo: $timestamp');
  }

  /// Retorna timestamp com margem de segurança para usuários
  /// Se última sync foi às 10:00, retorna 09:40 (20min antes)
  Future<String?> getSafeSyncParamUsers() async {
    final lastSync = await getLastSyncUsers();
    if (lastSync == null) return null;

    try {
      final lastSyncTime = DateTime.parse(lastSync);
      final safeTime = lastSyncTime.subtract(_safetyBuffer);
      final safeTimestamp = safeTime.toIso8601String();

      print('🛡️ [SyncManager] Users - Última sync: $lastSync → Com buffer: $safeTimestamp (${_safetyBuffer.inMinutes}min antes)');
      return safeTimestamp;
    } catch (e) {
      print('⚠️ [SyncManager] Erro ao aplicar buffer em users: $e');
      return null;
    }
  }

  /// Retorna timestamp com margem de segurança para pessoas
  Future<String?> getSafeSyncParamPeople() async {
    final lastSync = await getLastSyncPeople();
    if (lastSync == null) return null;

    try {
      final lastSyncTime = DateTime.parse(lastSync);
      final safeTime = lastSyncTime.subtract(_safetyBuffer);
      final safeTimestamp = safeTime.toIso8601String();

      print('🛡️ [SyncManager] People - Última sync: $lastSync → Com buffer: $safeTimestamp (${_safetyBuffer.inMinutes}min antes)');
      return safeTimestamp;
    } catch (e) {
      print('⚠️ [SyncManager] Erro ao aplicar buffer em people: $e');
      return null;
    }
  }

  /// Retorna timestamp com margem de segurança para alunos
  Future<String?> getSafeSyncParamStudents() async {
    final lastSync = await getLastSyncStudents();
    if (lastSync == null) return null;

    try {
      final lastSyncTime = DateTime.parse(lastSync);
      final safeTime = lastSyncTime.subtract(_safetyBuffer);
      final safeTimestamp = safeTime.toIso8601String();

      print('🛡️ [SyncManager] Students - Última sync: $lastSync → Com buffer: $safeTimestamp (${_safetyBuffer.inMinutes}min antes)');
      return safeTimestamp;
    } catch (e) {
      print('⚠️ [SyncManager] Erro ao aplicar buffer em students: $e');
      return null;
    }
  }

  /// Retorna timestamp com margem de segurança para logs
  Future<String?> getSafeSyncParamLogs() async {
    final lastSync = await getLastSyncLogs();
    if (lastSync == null) return null;

    try {
      final lastSyncTime = DateTime.parse(lastSync);
      final safeTime = lastSyncTime.subtract(_safetyBuffer);
      final safeTimestamp = safeTime.toIso8601String();

      print('🛡️ [SyncManager] Logs - Última sync: $lastSync → Com buffer: $safeTimestamp (${_safetyBuffer.inMinutes}min antes)');
      return safeTimestamp;
    } catch (e) {
      print('⚠️ [SyncManager] Erro ao aplicar buffer em logs: $e');
      return null;
    }
  }

  /// Retorna timestamp com margem de segurança para quartos
  Future<String?> getSafeSyncParamQuartos() async {
    final lastSync = await getLastSyncQuartos();
    if (lastSync == null) return null;

    try {
      final lastSyncTime = DateTime.parse(lastSync);
      final safeTime = lastSyncTime.subtract(_safetyBuffer);
      final safeTimestamp = safeTime.toIso8601String();

      print('🛡️ [SyncManager] Quartos - Última sync: $lastSync → Com buffer: $safeTimestamp (${_safetyBuffer.inMinutes}min antes)');
      return safeTimestamp;
    } catch (e) {
      print('⚠️ [SyncManager] Erro ao aplicar buffer em quartos: $e');
      return null;
    }
  }

  /// Retorna timestamp com margem de segurança para eventos
  Future<String?> getSafeSyncParamEventos() async {
    final lastSync = await getLastSyncEventos();
    if (lastSync == null) return null;

    try {
      final lastSyncTime = DateTime.parse(lastSync);
      final safeTime = lastSyncTime.subtract(_safetyBuffer);
      final safeTimestamp = safeTime.toIso8601String();

      print('🛡️ [SyncManager] Eventos - Última sync: $lastSync → Com buffer: $safeTimestamp (${_safetyBuffer.inMinutes}min antes)');
      return safeTimestamp;
    } catch (e) {
      print('⚠️ [SyncManager] Erro ao aplicar buffer em eventos: $e');
      return null;
    }
  }

  /// Limpa todos os timestamps de sincronização
  /// Usado quando precisa fazer uma sincronização completa do zero
  Future<void> clearAllSyncTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastSyncUsers);
    await prefs.remove(_keyLastSyncPeople);
    await prefs.remove(_keyLastSyncStudents);
    await prefs.remove(_keyLastSyncLogs);
    await prefs.remove(_keyLastSyncQuartos);
    await prefs.remove(_keyLastSyncEventos);
    print('🧹 [SyncManager] Todos os timestamps de sync foram limpos');
  }

  /// Retorna estatísticas de sincronização
  Future<Map<String, String?>> getSyncStats() async {
    return {
      'users': await getLastSyncUsers(),
      'people': await getLastSyncPeople(),
      'students': await getLastSyncStudents(),
      'logs': await getLastSyncLogs(),
      'quartos': await getLastSyncQuartos(),
      'eventos': await getLastSyncEventos(),
    };
  }

  /// Verifica se há alguma sincronização salva
  Future<bool> hasAnySyncTimestamp() async {
    final stats = await getSyncStats();
    return stats.values.any((timestamp) => timestamp != null);
  }
}
