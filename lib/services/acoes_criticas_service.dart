import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/firebase_service.dart';

/// Serviço para ações críticas do sistema usando Firebase
/// ATENÇÃO: Métodos destrutivos que apagam dados permanentemente!
class AcoesCriticasService {
  static final AcoesCriticasService _instance = AcoesCriticasService._internal();
  factory AcoesCriticasService() => _instance;
  static AcoesCriticasService get instance => _instance;

  AcoesCriticasService._internal();

  final _db = DatabaseHelper.instance;
  final _firebaseService = FirebaseService.instance;

  // =========================================================================
  // 1. LISTAR VIAGENS DISPONÍVEIS
  // =========================================================================

  /// Lista todas as viagens únicas disponíveis (baseado em inicio_viagem e fim_viagem)
  /// Busca do Firebase
  ///
  /// Returns: Lista de viagens com { inicio_viagem, fim_viagem }
  Future<List<Map<String, String>>> listarViagens() async {
    try {
      print('📋 Listando viagens disponíveis do Firebase...');

      final viagens = await _firebaseService.listarViagens();

      print('✅ ${viagens.length} viagens encontradas');
      return viagens;
    } catch (e) {
      print('❌ Erro ao listar viagens: $e');
      rethrow;
    }
  }

  // =========================================================================
  // 2. ENCERRAR VIAGEM - Limpa TUDO (Firebase + Banco Local)
  // =========================================================================

  /// Encerra uma viagem ou todas as viagens
  ///
  /// ATENÇÃO: Esta operação apaga permanentemente:
  /// - Pessoas da aba PESSOAS (Firebase)
  /// - Logs da aba LOGS (Firebase)
  /// - Alunos da aba ALUNOS (Firebase)
  /// - Todas as tabelas locais (SQLite)
  ///
  /// Parâmetros:
  /// - inicioViagem: Data de início da viagem (formato: dd/MM/yyyy)
  /// - fimViagem: Data de fim da viagem (formato: dd/MM/yyyy)
  /// - Se ambos forem null, TODAS as viagens serão encerradas
  ///
  /// Returns: AcaoCriticaResult com sucesso e mensagem
  Future<AcaoCriticaResult> encerrarViagem({
    String? inicioViagem,
    String? fimViagem,
  }) async {
    try {
      if (inicioViagem != null && fimViagem != null) {
        print('🔴 [CRÍTICO] Encerrando viagem específica: $inicioViagem a $fimViagem...');
      } else {
        print('🔴 [CRÍTICO] Encerrando TODAS as viagens...');
      }

      // 1. Limpar Firebase
      print('🔄 Limpando Firebase...');
      await _firebaseService.encerrarViagem(
        inicioViagem: inicioViagem,
        fimViagem: fimViagem,
      );
      print('✅ Firebase atualizado');

      // 2. Limpar banco de dados local
      print('🔄 Limpando banco de dados local...');
      if (inicioViagem != null && fimViagem != null) {
        await _limparBancoDadosLocalFiltrado(inicioViagem, fimViagem);
      } else {
        await _limparBancoDadosLocal();
      }
      print('✅ Banco de dados local limpo');

      final mensagem = inicioViagem != null && fimViagem != null
          ? 'Viagem de $inicioViagem a $fimViagem encerrada com sucesso'
          : 'TODAS as viagens foram encerradas com sucesso';

      print('🎉 $mensagem');

      return AcaoCriticaResult(
        success: true,
        message: mensagem,
        totalRemovidos: 0, // Não temos contagem exata
        detalhes: {
          'firebase_limpo': true,
          'banco_local_limpo': true,
        },
      );
    } catch (e) {
      print('❌ Erro ao encerrar viagem: $e');
      return AcaoCriticaResult(
        success: false,
        message: 'Erro ao encerrar viagem: $e',
        totalRemovidos: 0,
        detalhes: {'erro': e.toString()},
      );
    }
  }

  // =========================================================================
  // 3. ENVIAR TODOS PARA QUARTO - Atualiza campo movimentacao
  // =========================================================================

  /// Atualiza o campo 'movimentacao' de TODAS as pessoas para "QUARTO"
  ///
  /// ATENÇÃO: Esta operação atualiza:
  /// - Todas as pessoas na aba PESSOAS (Firebase)
  /// - Todas as pessoas na tabela pessoas_facial (SQLite)
  ///
  /// Use caso:
  /// - Final do dia, todos voltam para o quarto
  /// - Reset de localização
  ///
  /// Returns: AcaoCriticaResult com sucesso e mensagem
  Future<AcaoCriticaResult> enviarTodosParaQuarto() async {
    try {
      print('🏨 Enviando todos para QUARTO...');

      // 1. Atualizar Firebase
      print('🔄 Atualizando Firebase...');
      await _firebaseService.enviarTodosParaQuarto();
      print('✅ Firebase atualizado');

      // 2. Atualizar banco de dados local
      print('🔄 Atualizando banco de dados local...');
      final db = await _db.database;
      final result = await db.update(
        'pessoas_facial',
        {'movimentacao': 'QUARTO'},
      );
      print('✅ $result pessoas atualizadas localmente');

      final mensagem = 'Todas as pessoas foram enviadas para QUARTO';
      print('🎉 $mensagem');

      return AcaoCriticaResult(
        success: true,
        message: mensagem,
        totalRemovidos: 0,
        detalhes: {
          'firebase_atualizado': true,
          'banco_local_atualizado': true,
          'pessoas_atualizadas_localmente': result,
        },
      );
    } catch (e) {
      print('❌ Erro ao enviar todos para quarto: $e');
      return AcaoCriticaResult(
        success: false,
        message: 'Erro ao enviar todos para quarto: $e',
        totalRemovidos: 0,
        detalhes: {'erro': e.toString()},
      );
    }
  }

  // =========================================================================
  // MÉTODOS AUXILIARES PRIVADOS
  // =========================================================================

  /// Limpa TODAS as tabelas do banco de dados local
  Future<void> _limparBancoDadosLocal() async {
    final db = await _db.database;

    // Limpar tabela de pessoas_facial
    await db.delete('pessoas_facial');
    print('  ✅ Tabela pessoas_facial limpa');

    // Limpar tabela de logs
    await db.delete('logs');
    print('  ✅ Tabela logs limpa');

    // Limpar tabela de alunos
    await db.delete('alunos');
    print('  ✅ Tabela alunos limpa');

    // Limpar tabela de quartos
    await db.delete('quartos');
    print('  ✅ Tabela quartos limpa');

    // Limpar tabela de passageiros
    await db.delete('passageiros');
    print('  ✅ Tabela passageiros limpa');

    // Limpar sync_queue (fila de sincronização)
    await db.delete('sync_queue');
    print('  ✅ Tabela sync_queue limpa');
  }

  /// Limpa apenas os dados de uma viagem específica do banco de dados local
  Future<void> _limparBancoDadosLocalFiltrado(String inicioViagem, String fimViagem) async {
    final db = await _db.database;

    // Limpar pessoas_facial da viagem
    final pessoasRemovidas = await db.delete(
      'pessoas_facial',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );
    print('  ✅ $pessoasRemovidas pessoas removidas');

    // Limpar logs da viagem
    final logsRemovidos = await db.delete(
      'logs',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );
    print('  ✅ $logsRemovidos logs removidos');

    // Limpar alunos da viagem
    final alunosRemovidos = await db.delete(
      'alunos',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );
    print('  ✅ $alunosRemovidos alunos removidos');

    // Limpar quartos da viagem
    final quartosRemovidos = await db.delete(
      'quartos',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );
    print('  ✅ $quartosRemovidos quartos removidos');
  }
}

// =========================================================================
// CLASSE DE RESULTADO
// =========================================================================

/// Resultado de uma ação crítica
class AcaoCriticaResult {
  final bool success;
  final String message;
  final int totalRemovidos;
  final Map<String, dynamic>? detalhes;

  AcaoCriticaResult({
    required this.success,
    required this.message,
    required this.totalRemovidos,
    this.detalhes,
  });

  @override
  String toString() {
    return 'AcaoCriticaResult(success: $success, message: $message, totalRemovidos: $totalRemovidos, detalhes: $detalhes)';
  }
}
