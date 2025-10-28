import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:embarqueellus/models/passageiro.dart';

/// DatabaseHelper - Gerenciamento robusto de dados offline
///
/// Tabelas:
/// - passageiros: dados dos alunos para embarque/retorno
/// - alunos: dados dos alunos para reconhecimento facial (NOVA)
/// - embeddings: características faciais
/// - logs: histórico de passagens
/// - outbox: fila de sincronização pendente
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
      version: 3, // ✅ VERSÃO ATUALIZADA
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Criar estrutura inicial do banco
  Future<void> _onCreate(Database db, int version) async {
    print('🗂️ Criando estrutura do banco de dados v$version');

    // =========================================================================
    // TABELA 1: PASSAGEIROS (para embarque/retorno)
    // =========================================================================
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

    // =========================================================================
    // TABELA 2: ALUNOS (para reconhecimento facial) ✅ NOVA
    // =========================================================================
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

    // =========================================================================
    // TABELA 3: EMBEDDINGS (características faciais)
    // =========================================================================
    await db.execute('''
      CREATE TABLE embeddings (
        cpf TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        embedding TEXT NOT NULL,
        data_cadastro TEXT,
        FOREIGN KEY (cpf) REFERENCES alunos(cpf)
      )
    ''');

    // =========================================================================
    // TABELA 4: LOGS (histórico de passagens)
    // =========================================================================
    await db.execute('''
      CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cpf TEXT NOT NULL,
        personName TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        confidence REAL DEFAULT 0.95,
        tipo TEXT NOT NULL,
        sincronizado INTEGER DEFAULT 0,
        FOREIGN KEY (cpf) REFERENCES alunos(cpf)
      )
    ''');

    // =========================================================================
    // TABELA 5: OUTBOX (fila de sincronização)
    // =========================================================================
    await db.execute('''
      CREATE TABLE outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT NOT NULL,
        payload TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        tentativas INTEGER DEFAULT 0
      )
    ''');

    // =========================================================================
    // TABELA 6: SYNC_QUEUE (compatibilidade)
    // =========================================================================
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT NOT NULL,
        dados TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        tentativas INTEGER DEFAULT 0
      )
    ''');

    // =========================================================================
    // TABELA 7: METADATA
    // =========================================================================
    await db.execute('''
      CREATE TABLE metadata (
        chave TEXT PRIMARY KEY,
        valor TEXT,
        timestamp TEXT
      )
    ''');

    // =========================================================================
    // ÍNDICES PARA PERFORMANCE
    // =========================================================================
    await db.execute('CREATE INDEX idx_passageiros_cpf ON passageiros(cpf)');
    await db.execute('CREATE INDEX idx_passageiros_embarque ON passageiros(embarque)');

    await db.execute('CREATE INDEX idx_alunos_cpf ON alunos(cpf)');
    await db.execute('CREATE INDEX idx_alunos_facial ON alunos(facial)');

    await db.execute('CREATE INDEX idx_embeddings_cpf ON embeddings(cpf)');

    await db.execute('CREATE INDEX idx_logs_timestamp ON logs(timestamp DESC)');
    await db.execute('CREATE INDEX idx_logs_cpf ON logs(cpf)');
    await db.execute('CREATE INDEX idx_logs_tipo ON logs(tipo)');

    await db.execute('CREATE INDEX idx_outbox_tipo ON outbox(tipo)');

    print('✅ Banco de dados criado com sucesso');
  }

  /// Upgrade do banco de dados
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
    final List<Map<String, dynamic>> maps = await db.query('passageiros');

    return List.generate(maps.length, (i) {
      return Passageiro(
        nome: maps[i]['nome'],
        cpf: maps[i]['cpf'],
        idPasseio: maps[i]['id_passeio'] ?? '',
        turma: maps[i]['turma'] ?? '',
        embarque: maps[i]['embarque'] ?? 'NÃO',
        retorno: maps[i]['retorno'] ?? 'NÃO',
        onibus: maps[i]['onibus'] ?? '',
        codigoPulseira: maps[i]['codigo_pulseira'],
      );
    });
  }

  /// Buscar passageiros por ônibus
  Future<List<Passageiro>> getPassageirosByOnibus(String onibus) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'passageiros',
      where: 'onibus = ?',
      whereArgs: [onibus],
    );

    return List.generate(maps.length, (i) {
      return Passageiro(
        nome: maps[i]['nome'],
        cpf: maps[i]['cpf'],
        idPasseio: maps[i]['id_passeio'] ?? '',
        turma: maps[i]['turma'] ?? '',
        embarque: maps[i]['embarque'] ?? 'NÃO',
        retorno: maps[i]['retorno'] ?? 'NÃO',
        onibus: maps[i]['onibus'] ?? '',
        codigoPulseira: maps[i]['codigo_pulseira'],
      );
    });
  }

  /// Buscar passageiro por CPF
  Future<Passageiro?> getPassageiroByCpf(String cpf) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'passageiros',
      where: 'cpf = ?',
      whereArgs: [cpf],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    return Passageiro(
      nome: maps[0]['nome'],
      cpf: maps[0]['cpf'],
      idPasseio: maps[0]['id_passeio'] ?? '',
      turma: maps[0]['turma'] ?? '',
      embarque: maps[0]['embarque'] ?? 'NÃO',
      retorno: maps[0]['retorno'] ?? 'NÃO',
      onibus: maps[0]['onibus'] ?? '',
      codigoPulseira: maps[0]['codigo_pulseira'],
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
  // OPERAÇÕES COM ALUNOS (Reconhecimento Facial) ✅ NOVO
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
      {String? fotoBase64}) async {
    await insertEmbedding({
      'cpf': cpf,
      'nome': '', // Será preenchido se necessário
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
    required DateTime timestamp,
    required double confidence,
    required String tipo,
  }) async {
    final db = await database;
    await db.insert('logs', {
      'cpf': cpf,
      'personName': personName,
      'timestamp': timestamp.toIso8601String(),
      'confidence': confidence,
      'tipo': tipo,
      'sincronizado': 0,
    });
  }

  /// Buscar logs de hoje
  Future<List<Map<String, dynamic>>> getLogsHoje() async {
    final db = await database;

    final now = DateTime.now();
    final inicio = DateTime(now.year, now.month, now.day).toIso8601String();
    final fim = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

    return db.query(
      'logs',
      where: 'timestamp BETWEEN ? AND ?',
      whereArgs: [inicio, fim],
      orderBy: 'timestamp DESC',
    );
  }

  // =========================================================================
  // FILA DE SINCRONIZAÇÃO (OUTBOX)
  // =========================================================================

  /// Enfileirar item para sincronização
  Future<int> enqueueOutbox(String tipo, Map<String, dynamic> payload) async {
    final db = await database;
    return db.insert('outbox', {
      'tipo': tipo,
      'payload': jsonEncode(payload),
      'createdAt': DateTime.now().toIso8601String(),
      'tentativas': 0,
    });
  }

  /// Obter lote da fila
  Future<List<Map<String, dynamic>>> getOutboxBatch({int limit = 50}) async {
    final db = await database;
    return db.query('outbox', orderBy: 'id ASC', limit: limit);
  }

  /// Remover itens da fila
  Future<void> deleteOutboxIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final qMarks = List.filled(ids.length, '?').join(',');
    await db.rawDelete('DELETE FROM outbox WHERE id IN ($qMarks)', ids);
  }

  // =========================================================================
  // FILA DE SINCRONIZAÇÃO (SYNC_QUEUE) - Compatibilidade
  // =========================================================================

  /// Adicionar item à fila de sincronização
  Future<void> addToSyncQueue(String tipo, Map<String, dynamic> dados) async {
    final db = await database;

    await db.insert('sync_queue', {
      'tipo': tipo,
      'dados': jsonEncode(dados),
      'timestamp': DateTime.now().toIso8601String(),
      'tentativas': 0,
    });

    print('📤 Adicionado à fila de sync: $tipo');
  }

  /// Obter itens pendentes de sincronização
  Future<List<Map<String, dynamic>>> getPendingSync() async {
    final db = await database;
    return await db.query(
      'sync_queue',
      orderBy: 'timestamp ASC',
      limit: 50,
    );
  }

  /// Remover item da fila após sincronização bem-sucedida
  Future<void> removeFromSyncQueue(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  /// Incrementar tentativas de sincronização
  Future<void> incrementSyncAttempts(int id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE sync_queue SET tentativas = tentativas + 1 WHERE id = ?',
      [id],
    );
  }

  /// Limpar fila de sincronização
  Future<void> clearSyncQueue() async {
    final db = await database;
    await db.delete('sync_queue');
    print('🗑️ Fila de sincronização limpa');
  }

  // =========================================================================
  // METADADOS
  // =========================================================================

  /// Salvar metadado
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

  /// Obter metadado
  Future<String?> getMetadata(String chave) async {
    final db = await database;

    final result = await db.query(
      'metadata',
      columns: ['valor'],
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
        await db.rawQuery('SELECT COUNT(*) FROM sync_queue'));

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