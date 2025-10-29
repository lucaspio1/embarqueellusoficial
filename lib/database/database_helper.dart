// lib/database/database_helper.dart
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:embarqueellus/models/passageiro.dart';

/// DatabaseHelper - Gerenciamento robusto de dados offline
///
/// ✅ VERSÃO ATUALIZADA COM:
/// - Métodos para buscar apenas alunos embarcados (cadastro facial)
/// - Métodos para buscar todos alunos com facial (reconhecimento)
/// - Prevenção de duplicatas em logs
/// - Índices otimizados
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'embarque_ellus.db');

    print('📂 Inicializando banco de dados em: $path');

    return await openDatabase(
      path,
      version: 4, // ✅ VERSÃO ATUALIZADA DE 3 PARA 4
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Criar estrutura inicial do banco
  Future<void> _onCreate(Database db, int version) async {
    print('🗂️ Criando estrutura do banco de dados v$version');

    // TABELA 1: PASSAGEIROS (para embarque/retorno)
    await db.execute('''
      CREATE TABLE passageiros (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cpf TEXT UNIQUE NOT NULL,
        nome TEXT NOT NULL,
        id_passeio TEXT,
        turma TEXT,
        onibus TEXT,
        embarque TEXT DEFAULT 'NÃO',
        retorno TEXT DEFAULT 'NÃO',
        codigo_pulseira TEXT,
        data_cadastro TEXT,
        ultima_atualizacao TEXT
      )
    ''');

    // TABELA 2: ALUNOS (para reconhecimento facial)
    await db.execute('''
      CREATE TABLE alunos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cpf TEXT UNIQUE NOT NULL,
        nome TEXT NOT NULL,
        email TEXT,
        telefone TEXT,
        turma TEXT,
        facial TEXT DEFAULT NULL,
        data_cadastro TEXT,
        ultima_atualizacao TEXT
      )
    ''');

    // TABELA 3: EMBEDDINGS (características faciais)
    await db.execute('''
      CREATE TABLE embeddings (
        cpf TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        embedding TEXT NOT NULL,
        data_cadastro TEXT
      )
    ''');

    // TABELA 4: LOGS (histórico de passagens)
    await db.execute('''
      CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cpf TEXT NOT NULL,
        personName TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        confidence REAL DEFAULT 0.95,
        tipo TEXT NOT NULL,
        sincronizado INTEGER DEFAULT 0
      )
    ''');

    // TABELA 5: SYNC_QUEUE (fila de sincronização)
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT NOT NULL,
        payload TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        tentativas INTEGER DEFAULT 0,
        sincronizado INTEGER DEFAULT 0
      )
    ''');

    // TABELA 6: OUTBOX (fila de sincronização legada)
    await db.execute('''
      CREATE TABLE outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT NOT NULL,
        payload TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        tentativas INTEGER DEFAULT 0
      )
    ''');

    // TABELA 7: METADATA
    await db.execute('''
      CREATE TABLE metadata (
        chave TEXT PRIMARY KEY,
        valor TEXT,
        timestamp TEXT
      )
    ''');

    // ✅ ÍNDICES PARA PERFORMANCE
    await db.execute('CREATE INDEX idx_passageiros_cpf ON passageiros(cpf)');
    await db.execute('CREATE INDEX idx_passageiros_embarque ON passageiros(embarque)');

    await db.execute('CREATE INDEX idx_alunos_cpf ON alunos(cpf)');
    await db.execute('CREATE INDEX idx_alunos_facial ON alunos(facial)');

    await db.execute('CREATE INDEX idx_embeddings_cpf ON embeddings(cpf)');

    await db.execute('CREATE INDEX idx_logs_timestamp ON logs(timestamp DESC)');
    await db.execute('CREATE INDEX idx_logs_cpf ON logs(cpf)');
    await db.execute('CREATE INDEX idx_logs_tipo ON logs(tipo)');

    // ✅ NOVO: Índice composto para prevenir duplicatas
    await db.execute('CREATE INDEX idx_logs_duplicata ON logs(cpf, tipo, timestamp)');

    print('✅ Banco de dados criado com sucesso');
  }

  /// ✅ ATUALIZADO: Upgrade do banco de dados
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('⬆️ Atualizando banco de $oldVersion para $newVersion');

    if (oldVersion < 2) {
      // Adicionar tabelas de facial se não existirem
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS embeddings (
            cpf TEXT PRIMARY KEY,
            nome TEXT NOT NULL,
            embedding TEXT NOT NULL,
            data_cadastro TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cpf TEXT NOT NULL,
            personName TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            confidence REAL DEFAULT 0.95,
            tipo TEXT NOT NULL,
            sincronizado INTEGER DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tipo TEXT NOT NULL,
            payload TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            tentativas INTEGER DEFAULT 0
          )
        ''');

        print('✅ Tabelas de reconhecimento facial adicionadas');
      } catch (e) {
        print('⚠️ Tabelas já existem ou erro: $e');
      }
    }

    if (oldVersion < 3) {
      // Adicionar tabela ALUNOS
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS alunos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cpf TEXT UNIQUE NOT NULL,
            nome TEXT NOT NULL,
            email TEXT,
            telefone TEXT,
            turma TEXT,
            facial TEXT DEFAULT NULL,
            data_cadastro TEXT,
            ultima_atualizacao TEXT
          )
        ''');

        await db.execute('CREATE INDEX IF NOT EXISTS idx_alunos_cpf ON alunos(cpf)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_alunos_facial ON alunos(facial)');

        print('✅ Tabela ALUNOS criada');
      } catch (e) {
        print('⚠️ Tabela ALUNOS já existe ou erro: $e');
      }
    }

    // ✅ NOVO: Versão 4 - Prevenir duplicatas
    if (oldVersion < 4) {
      try {
        // Adicionar índice composto para prevenir duplicatas na tabela logs
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_logs_duplicata 
          ON logs(cpf, tipo, timestamp)
        ''');

        print('✅ Índice anti-duplicata criado');
      } catch (e) {
        print('⚠️ Erro ao criar índice: $e');
      }
    }
  }

  // =========================================================================
  // ✅ NOVOS MÉTODOS ESPECÍFICOS PARA CADASTRO E RECONHECIMENTO
  // =========================================================================

  /// ✅ BUSCAR APENAS ALUNOS EMBARCADOS (para CADASTRO facial)
  /// Use na tela de cadastro facial - só mostra quem está embarcado
  Future<List<Map<String, dynamic>>> getAlunosEmbarcadosParaCadastro() async {
    final db = await database;

    // Busca alunos que estão na tabela PASSAGEIROS com embarque = 'SIM'
    final resultado = await db.rawQuery('''
      SELECT DISTINCT 
        p.cpf,
        p.nome,
        p.turma,
        p.codigo_pulseira,
        a.facial,
        a.email,
        a.telefone
      FROM passageiros p
      LEFT JOIN alunos a ON p.cpf = a.cpf
      WHERE p.embarque = 'SIM'
      ORDER BY p.nome ASC
    ''');

    print('📋 [DatabaseHelper] Alunos embarcados para cadastro: ${resultado.length}');
    return resultado;
  }

  /// ✅ BUSCAR TODOS OS ALUNOS COM FACIAL (para RECONHECIMENTO)
  /// Use na tela de reconhecimento - busca TODOS que têm face cadastrada
  Future<List<Map<String, dynamic>>> getTodosAlunosComFacial() async {
    final db = await database;

    // Busca TODOS os alunos que têm embedding cadastrado
    final resultado = await db.rawQuery('''
      SELECT 
        a.cpf,
        a.nome,
        a.turma,
        a.email,
        a.telefone,
        e.embedding
      FROM alunos a
      INNER JOIN embeddings e ON a.cpf = e.cpf
      WHERE a.facial = 'CADASTRADA'
      ORDER BY a.nome ASC
    ''');

    print('🔍 [DatabaseHelper] Total de alunos com facial: ${resultado.length}');
    return resultado;
  }

  /// ✅ REGISTRAR PASSAGEM SEM DUPLICATA
  /// Previne registrar a mesma pessoa no mesmo local no mesmo minuto
  Future<bool> registrarPassagemSemDuplicata({
    required String cpf,
    required String personName,
    required String local,
    required String tipo,
  }) async {
    final db = await database;
    final agora = DateTime.now();

    // Arredondar para o minuto (ignora segundos)
    final timestampMinuto = DateTime(
      agora.year,
      agora.month,
      agora.day,
      agora.hour,
      agora.minute,
    );

    try {
      // Verificar se já existe registro com mesmo CPF, tipo e minuto
      final existente = await db.query(
        'logs',
        where: 'cpf = ? AND tipo = ? AND timestamp LIKE ?',
        whereArgs: [
          cpf,
          tipo,
          '${timestampMinuto.toIso8601String().substring(0, 16)}%', // Compara até minuto
        ],
        limit: 1,
      );

      if (existente.isNotEmpty) {
        print('⚠️ [DatabaseHelper] Passagem duplicada ignorada: $personName ($tipo)');
        return false; // Duplicata detectada
      }

      // Inserir novo registro
      await db.insert('logs', {
        'cpf': cpf,
        'personName': personName,
        'timestamp': agora.toIso8601String(),
        'confidence': 0.95,
        'tipo': tipo,
        'sincronizado': 0,
      });

      print('✅ [DatabaseHelper] Passagem registrada: $personName - $local ($tipo)');

      // Adicionar à fila de sincronização
      await addToSyncQueue('log_passagem', {
        'cpf': cpf,
        'nome': personName,
        'local': local,
        'tipo': tipo,
        'timestamp': agora.toIso8601String(),
      });

      return true; // Sucesso

    } catch (e) {
      print('❌ [DatabaseHelper] Erro ao registrar passagem: $e');
      return false;
    }
  }

  // =========================================================================
  // OPERAÇÕES COM PASSAGEIROS (Embarque/Retorno)
  // =========================================================================

  /// Inserir ou atualizar passageiro
  Future<int> upsertPassageiro(Passageiro passageiro) async {
    final db = await database;

    try {
      final existing = await db.query(
        'passageiros',
        where: 'cpf = ?',
        whereArgs: [passageiro.cpf],
      );

      final data = {
        'cpf': passageiro.cpf,
        'nome': passageiro.nome,
        'id_passeio': passageiro.idPasseio,
        'turma': passageiro.turma,
        'onibus': passageiro.onibus,
        'embarque': passageiro.embarque,
        'retorno': passageiro.retorno,
        'codigo_pulseira': passageiro.codigoPulseira,
        'ultima_atualizacao': DateTime.now().toIso8601String(),
      };

      if (existing.isEmpty) {
        data['data_cadastro'] = DateTime.now().toIso8601String();
        return await db.insert('passageiros', data);
      } else {
        await db.update(
          'passageiros',
          data,
          where: 'cpf = ?',
          whereArgs: [passageiro.cpf],
        );
        return existing.first['id'] as int;
      }
    } catch (e) {
      print('❌ Erro ao salvar passageiro: $e');
      rethrow;
    }
  }

  /// Buscar todos os passageiros
  Future<List<Passageiro>> getAllPassageiros() async {
    final db = await database;
    final maps = await db.query('passageiros', orderBy: 'nome ASC');
    return maps.map((map) => Passageiro.fromMap(map)).toList();
  }

  /// Buscar passageiro por CPF
  Future<Passageiro?> getPassageiroByCpf(String cpf) async {
    final db = await database;
    final maps = await db.query(
      'passageiros',
      where: 'cpf = ?',
      whereArgs: [cpf],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    return Passageiro(
      cpf: maps[0]['cpf'] as String,
      nome: maps[0]['nome'] as String,
      idPasseio: maps[0]['id_passeio'] as String?,
      turma: maps[0]['turma'] as String?,
      embarque: maps[0]['embarque'] as String? ?? 'NÃO',
      retorno: maps[0]['retorno'] as String? ?? 'NÃO',
      onibus: maps[0]['onibus'] as String? ?? '',
      codigoPulseira: maps[0]['codigo_pulseira'] as String?,
    );
  }

  /// Atualizar status de embarque
  Future<void> updateEmbarque(String cpf, String status,
      {String? codigoPulseira}) async {
    final db = await database;

    final data = {
      'embarque': status,
      'ultima_atualizacao': DateTime.now().toIso8601String(),
    };

    if (codigoPulseira != null) {
      data['codigo_pulseira'] = codigoPulseira;
    }

    await db.update(
      'passageiros',
      data,
      where: 'cpf = ?',
      whereArgs: [cpf],
    );

    await addToSyncQueue('embarque', {
      'cpf': cpf,
      'novoStatus': status,
      'codigoPulseira': codigoPulseira,
    });
  }

  /// Atualizar status de retorno
  Future<void> updateRetorno(String cpf, String status) async {
    final db = await database;

    await db.update(
      'passageiros',
      {
        'retorno': status,
        'ultima_atualizacao': DateTime.now().toIso8601String(),
      },
      where: 'cpf = ?',
      whereArgs: [cpf],
    );

    await addToSyncQueue('retorno', {
      'cpf': cpf,
      'novoRetorno': status,
    });
  }

  /// Limpar todos os passageiros
  Future<void> clearAllPassageiros() async {
    final db = await database;
    await db.delete('passageiros');
    print('🗑️ Todos os passageiros removidos');
  }

  // =========================================================================
  // OPERAÇÕES COM ALUNOS (Reconhecimento Facial)
  // =========================================================================

  /// Buscar todos os alunos
  Future<List<Map<String, dynamic>>> getAllAlunos() async {
    final db = await database;
    return await db.query('alunos', orderBy: 'nome ASC');
  }

  /// Inserir ou atualizar aluno
  Future<int> upsertAluno(Map<String, dynamic> aluno) async {
    final db = await database;

    try {
      final existing = await db.query(
        'alunos',
        where: 'cpf = ?',
        whereArgs: [aluno['cpf']],
      );

      final data = {
        'cpf': aluno['cpf'],
        'nome': aluno['nome'],
        'email': aluno['email'],
        'telefone': aluno['telefone'],
        'turma': aluno['turma'],
        'facial': aluno['facial'],
        'ultima_atualizacao': DateTime.now().toIso8601String(),
      };

      if (existing.isEmpty) {
        data['data_cadastro'] = DateTime.now().toIso8601String();
        return await db.insert('alunos', data);
      } else {
        await db.update(
          'alunos',
          data,
          where: 'cpf = ?',
          whereArgs: [aluno['cpf']],
        );
        return existing.first['id'] as int;
      }
    } catch (e) {
      print('❌ Erro ao salvar aluno: $e');
      rethrow;
    }
  }

  /// Atualizar status facial do aluno
  Future<void> updateAlunoFacial(String cpf, String status) async {
    final db = await database;
    await db.update(
      'alunos',
      {
        'facial': status,
        'ultima_atualizacao': DateTime.now().toIso8601String(),
      },
      where: 'cpf = ?',
      whereArgs: [cpf],
    );
  }

  /// Buscar aluno por CPF
  Future<Map<String, dynamic>?> getAlunoByCpf(String cpf) async {
    final db = await database;
    final result = await db.query(
      'alunos',
      where: 'cpf = ?',
      whereArgs: [cpf],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  // =========================================================================
  // OPERAÇÕES COM EMBEDDINGS
  // =========================================================================

  /// Salvar embedding facial
  Future<void> insertEmbedding(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'embeddings',
      {
        'cpf': data['cpf'],
        'nome': data['nome'],
        'embedding': data['embedding'].toString(),
        'data_cadastro': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Buscar todos os embeddings
  Future<List<Map<String, dynamic>>> getAllEmbeddings() async {
    final db = await database;
    final result = await db.query('embeddings');
    return result.map((e) {
      return {
        'cpf': e['cpf'],
        'nome': e['nome'],
        'embedding': (e['embedding'] as String)
            .replaceAll('[', '')
            .replaceAll(']', '')
            .split(',')
            .map((v) => double.tryParse(v.trim()) ?? 0.0)
            .toList(),
      };
    }).toList();
  }

  /// Salvar embedding (método legado para compatibilidade)
  Future<void> saveEmbedding(String cpf, List<double> embedding,
      {String? nome}) async {
    await insertEmbedding({
      'cpf': cpf,
      'nome': nome ?? 'Desconhecido',
      'embedding': embedding,
    });
  }

  // =========================================================================
  // OPERAÇÕES COM LOGS
  // =========================================================================

  /// Inserir log de passagem
  Future<void> insertLog({
    required String cpf,
    required String personName,
    required double confidence,
    required String tipo,
  }) async {
    final db = await database;
    await db.insert('logs', {
      'cpf': cpf,
      'personName': personName,
      'timestamp': DateTime.now().toIso8601String(),
      'confidence': confidence,
      'tipo': tipo,
      'sincronizado': 0,
    });
  }

  /// Buscar logs de hoje
  Future<List<Map<String, dynamic>>> getLogsHoje() async {
    final db = await database;
    final hoje = DateTime.now();
    final inicioDia = DateTime(hoje.year, hoje.month, hoje.day).toIso8601String();

    return await db.query(
      'logs',
      where: 'timestamp >= ?',
      whereArgs: [inicioDia],
      orderBy: 'timestamp DESC',
    );
  }

  /// Buscar todos os logs
  Future<List<Map<String, dynamic>>> getAllLogs({int? limit}) async {
    final db = await database;
    return await db.query(
      'logs',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  // =========================================================================
  // SINCRONIZAÇÃO
  // =========================================================================

  /// Adicionar à fila de sincronização
  Future<void> addToSyncQueue(String tipo, Map<String, dynamic> payload) async {
    final db = await database;
    await db.insert('sync_queue', {
      'tipo': tipo,
      'payload': jsonEncode(payload),
      'timestamp': DateTime.now().toIso8601String(),
      'tentativas': 0,
      'sincronizado': 0,
    });
  }

  /// Buscar itens pendentes de sincronização
  Future<List<Map<String, dynamic>>> getPendingSync() async {
    final db = await database;
    return await db.query(
      'sync_queue',
      where: 'sincronizado = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
    );
  }

  /// Marcar item como sincronizado
  Future<void> markAsSynced(int id) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // =========================================================================
  // METADATA
  // =========================================================================

  /// Salvar metadata
  Future<void> setMetadata(String chave, String valor) async {
    final db = await database;
    await db.insert(
      'metadata',
      {
        'chave': chave,
        'valor': valor,
        'timestamp': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Buscar metadata
  Future<String?> getMetadata(String chave) async {
    final db = await database;
    final result = await db.query(
      'metadata',
      where: 'chave = ?',
      whereArgs: [chave],
      limit: 1,
    );

    return result.isNotEmpty ? result.first['valor'] as String? : null;
  }

  // =========================================================================
  // ESTATÍSTICAS
  // =========================================================================

  /// Obter estatísticas gerais
  Future<Map<String, int>> getStats() async {
    final db = await database;

    final totalPassageiros = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM passageiros'));

    final embarcados = Sqflite.firstIntValue(await db
        .rawQuery("SELECT COUNT(*) FROM passageiros WHERE embarque = 'SIM'"));

    final retornados = Sqflite.firstIntValue(await db
        .rawQuery("SELECT COUNT(*) FROM passageiros WHERE retorno = 'SIM'"));

    final totalAlunos = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM alunos'));

    final alunosComFacial = Sqflite.firstIntValue(await db
        .rawQuery("SELECT COUNT(*) FROM alunos WHERE facial = 'CADASTRADA'"));

    final pendingSync = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM sync_queue WHERE sincronizado = 0'));

    final logsHoje = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM logs WHERE date(timestamp) = date('now')"));

    return {
      'total_passageiros': totalPassageiros ?? 0,
      'embarcados': embarcados ?? 0,
      'retornados': retornados ?? 0,
      'total_alunos': totalAlunos ?? 0,
      'alunos_com_facial': alunosComFacial ?? 0,
      'pendentes_sync': pendingSync ?? 0,
      'logs_hoje': logsHoje ?? 0,
    };
  }

  // =========================================================================
  // MANUTENÇÃO
  // =========================================================================

  /// Limpar dados antigos
  Future<void> cleanup({int daysToKeep = 30}) async {
    final db = await database;
    final cutoffDate = DateTime.now()
        .subtract(Duration(days: daysToKeep))
        .toIso8601String();

    await db.delete(
      'logs',
      where: 'timestamp < ? AND sincronizado = 1',
      whereArgs: [cutoffDate],
    );

    print('🧹 Limpeza de dados antigos concluída');
  }

  /// Garantir schema facial
  Future<void> ensureFacialSchema() async {
    final db = await database;

    // Verificar se tabela alunos existe
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='alunos'"
    );

    if (tables.isEmpty) {
      print('⚠️ Tabela ALUNOS não existe, criando...');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS alunos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cpf TEXT UNIQUE NOT NULL,
          nome TEXT NOT NULL,
          email TEXT,
          telefone TEXT,
          turma TEXT,
          facial TEXT DEFAULT NULL,
          data_cadastro TEXT,
          ultima_atualizacao TEXT
        )
      ''');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_alunos_cpf ON alunos(cpf)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_alunos_facial ON alunos(facial)');

      print('✅ Tabela ALUNOS criada com sucesso');
    }
  }

  /// Fechar banco de dados
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
    print('🔒 Banco de dados fechado');
  }
}