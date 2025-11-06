// lib/database/database_helper.dart - VERSÃO COMPLETA CORRIGIDA
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/passageiro.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'embarque.db');
    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Adicionar coluna operador_nome à tabela logs
      await db.execute('ALTER TABLE logs ADD COLUMN operador_nome TEXT');
      print('✅ [DB] Migração v1 -> v2: Adicionado campo operador_nome na tabela logs');
    }
    if (oldVersion < 3) {
      // Garantir coluna de movimentação em pessoas_facial
      try {
        await db.execute("ALTER TABLE pessoas_facial ADD COLUMN movimentacao TEXT");
        print('✅ [DB] Migração v2 -> v3: Adicionada coluna movimentacao na tabela pessoas_facial');
      } catch (e) {
        print('⚠️ [DB] Coluna movimentacao já existia: $e');
      }
    }
    if (oldVersion < 4) {
      // Adicionar colunas inicio_viagem e fim_viagem às tabelas
      try {
        await db.execute("ALTER TABLE passageiros ADD COLUMN inicio_viagem TEXT");
        await db.execute("ALTER TABLE passageiros ADD COLUMN fim_viagem TEXT");
        print('✅ [DB] Migração v3 -> v4: Adicionadas colunas de data em passageiros');
      } catch (e) {
        print('⚠️ [DB] Colunas de data já existiam em passageiros: $e');
      }

      try {
        await db.execute("ALTER TABLE alunos ADD COLUMN inicio_viagem TEXT");
        await db.execute("ALTER TABLE alunos ADD COLUMN fim_viagem TEXT");
        print('✅ [DB] Migração v3 -> v4: Adicionadas colunas de data em alunos');
      } catch (e) {
        print('⚠️ [DB] Colunas de data já existiam em alunos: $e');
      }

      try {
        await db.execute("ALTER TABLE pessoas_facial ADD COLUMN inicio_viagem TEXT");
        await db.execute("ALTER TABLE pessoas_facial ADD COLUMN fim_viagem TEXT");
        print('✅ [DB] Migração v3 -> v4: Adicionadas colunas de data em pessoas_facial');
      } catch (e) {
        print('⚠️ [DB] Colunas de data já existiam em pessoas_facial: $e');
      }

      try {
        await db.execute("ALTER TABLE logs ADD COLUMN inicio_viagem TEXT");
        await db.execute("ALTER TABLE logs ADD COLUMN fim_viagem TEXT");
        print('✅ [DB] Migração v3 -> v4: Adicionadas colunas de data em logs');
      } catch (e) {
        print('⚠️ [DB] Colunas de data já existiam em logs: $e');
      }
    }
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE passageiros(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        cpf TEXT,
        id_passeio TEXT,
        turma TEXT,
        embarque TEXT DEFAULT 'NÃO',
        retorno TEXT DEFAULT 'NÃO',
        onibus TEXT,
        codigo_pulseira TEXT,
        inicio_viagem TEXT,
        fim_viagem TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE alunos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cpf TEXT UNIQUE,
        nome TEXT,
        email TEXT,
        telefone TEXT,
        turma TEXT,
        facial TEXT,
        tem_qr TEXT DEFAULT 'NAO',
        created_at TEXT,
        inicio_viagem TEXT,
        fim_viagem TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE embeddings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cpf TEXT UNIQUE,
        nome TEXT,
        embedding TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE pessoas_facial(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cpf TEXT UNIQUE,
        nome TEXT,
        email TEXT,
        telefone TEXT,
        turma TEXT,
        embedding TEXT,
        facial_status TEXT DEFAULT 'CADASTRADA',
        movimentacao TEXT,
        created_at TEXT,
        updated_at TEXT,
        inicio_viagem TEXT,
        fim_viagem TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cpf TEXT,
        person_name TEXT,
        timestamp TEXT,
        confidence REAL,
        tipo TEXT,
        operador_nome TEXT,
        created_at TEXT,
        inicio_viagem TEXT,
        fim_viagem TEXT,
        UNIQUE(cpf, timestamp, tipo)
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT,
        payload TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE usuarios(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT,
        nome TEXT NOT NULL,
        cpf TEXT UNIQUE NOT NULL,
        senha_hash TEXT NOT NULL,
        perfil TEXT DEFAULT 'USUARIO',
        ativo INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
  }

  Future<void> ensureFacialSchema() async {
    final db = await database;

    try {
      await db.rawQuery('SELECT facial FROM alunos LIMIT 1');
    } catch (e) {
      await db.execute('ALTER TABLE alunos ADD COLUMN facial TEXT');
    }

    // Garantir que tem_qr existe
    try {
      await db.rawQuery('SELECT tem_qr FROM alunos LIMIT 1');
    } catch (e) {
      await db.execute('ALTER TABLE alunos ADD COLUMN tem_qr TEXT DEFAULT "NAO"');
      print('✅ Campo tem_qr adicionado à tabela alunos');
    }

    // Garantir que tabela usuarios existe
    try {
      await db.rawQuery('SELECT * FROM usuarios LIMIT 1');
      print('✅ Tabela usuarios já existe');
    } catch (e) {
      print('📝 Criando tabela usuarios...');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS usuarios(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT,
          nome TEXT NOT NULL,
          cpf TEXT UNIQUE NOT NULL,
          senha_hash TEXT NOT NULL,
          perfil TEXT DEFAULT 'USUARIO',
          ativo INTEGER DEFAULT 1,
          created_at TEXT,
          updated_at TEXT
        )
      ''');
      print('✅ Tabela usuarios criada');
    }

    // Garantir que tabela pessoas_facial existe
    try {
      await db.rawQuery('SELECT * FROM pessoas_facial LIMIT 1');
      print('✅ Tabela pessoas_facial já existe');
    } catch (e) {
      print('📝 Criando tabela pessoas_facial...');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pessoas_facial(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cpf TEXT UNIQUE,
          nome TEXT,
          email TEXT,
          telefone TEXT,
          turma TEXT,
          embedding TEXT,
          facial_status TEXT DEFAULT 'CADASTRADA',
          created_at TEXT,
          updated_at TEXT
        )
      ''');
      print('✅ Tabela pessoas_facial criada');
    }

    // 🔒 MIGRATION: Adicionar UNIQUE constraint na tabela logs
    // Verifica se precisa migrar (apps existentes sem a constraint)
    try {
      // Tenta inserir log duplicado para testar se constraint existe
      final testTimestamp = '2000-01-01T00:00:00.000Z';
      await db.insert('logs', {
        'cpf': 'TEST',
        'person_name': 'TEST',
        'timestamp': testTimestamp,
        'confidence': 0.0,
        'tipo': 'TEST',
        'created_at': testTimestamp,
      });
      // Tenta inserir novamente
      await db.insert('logs', {
        'cpf': 'TEST',
        'person_name': 'TEST',
        'timestamp': testTimestamp,
        'confidence': 0.0,
        'tipo': 'TEST',
        'created_at': testTimestamp,
      });
      // Se chegou aqui, constraint NÃO existe - precisa migrar!
      print('⚠️ UNIQUE constraint não encontrada na tabela logs - iniciando migração...');

      // Limpar logs de teste
      await db.delete('logs', where: 'cpf = ?', whereArgs: ['TEST']);

      // Backup dos dados atuais
      final logsBackup = await db.query('logs');

      // Dropar tabela antiga
      await db.execute('DROP TABLE logs');

      // Criar tabela nova com UNIQUE constraint
      await db.execute('''
        CREATE TABLE logs(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cpf TEXT,
          person_name TEXT,
          timestamp TEXT,
          confidence REAL,
          tipo TEXT,
          created_at TEXT,
          UNIQUE(cpf, timestamp, tipo)
        )
      ''');

      // Restaurar dados SEM duplicatas
      final Set<String> chavesDuplicatas = {};
      int duplicatasRemovidas = 0;

      for (final log in logsBackup) {
        final chave = '${log['cpf']}_${log['timestamp']}_${log['tipo']}';

        if (chavesDuplicatas.contains(chave)) {
          duplicatasRemovidas++;
          continue; // Pula duplicata
        }

        chavesDuplicatas.add(chave);

        try {
          await db.insert('logs', {
            'cpf': log['cpf'],
            'person_name': log['person_name'],
            'timestamp': log['timestamp'],
            'confidence': log['confidence'],
            'tipo': log['tipo'],
            'created_at': log['created_at'],
          });
        } catch (e) {
          print('⚠️ Erro ao restaurar log: $e');
        }
      }

      print('✅ Migração concluída: ${logsBackup.length - duplicatasRemovidas} logs únicos restaurados');
      if (duplicatasRemovidas > 0) {
        print('🗑️ $duplicatasRemovidas duplicatas removidas');
      }
    } catch (e) {
      // Se deu erro, significa que a constraint já existe ou outro erro
      // Limpar logs de teste se existirem
      try {
        await db.delete('logs', where: 'cpf = ?', whereArgs: ['TEST']);
      } catch (_) {}

      if (e.toString().contains('UNIQUE constraint failed')) {
        print('✅ UNIQUE constraint já existe na tabela logs');
      } else {
        print('ℹ️ Tabela logs já está atualizada ou erro ao verificar: ${e.toString()}');
      }
    }
  }

  // Métodos para passageiros
  Future<void> insertPassageiro(Passageiro passageiro) async {
    final db = await database;
    await db.insert('passageiros', passageiro.toMap());
  }

  Future<List<Passageiro>> getPassageiros() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('passageiros');
    return maps.map((map) => Passageiro.fromMap(map)).toList();
  }

  Future<List<Map<String, dynamic>>> getPassageirosEmbarcados() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'passageiros',
      where: 'embarque = ?',
      whereArgs: ['SIM'],
    );
    return maps;
  }

  Future<void> updatePassageiro(Passageiro passageiro) async {
    final db = await database;
    await db.update(
      'passageiros',
      passageiro.toMap(),
      where: 'cpf = ?',
      whereArgs: [passageiro.cpf],
    );
  }

  // Métodos para alunos
  Future<void> upsertAluno(Map<String, dynamic> aluno) async {
    final db = await database;
    await db.insert(
      'alunos',
      {
        ...aluno,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllAlunos() async {
    final db = await database;
    return await db.query('alunos');
  }

  // ========================================================================
  // AQUI ESTÁ A CORREÇÃO
  // ========================================================================

  /// Busca alunos que precisam de cadastro facial (facial = 'NAO' ou NULL)
  Future<List<Map<String, dynamic>>> getAlunosParaCadastroFacial() async {
    final db = await database;
    // Retorna alunos que AINDA NÃO têm facial (baseado no campo 'facial')
    return await db.query(
        'alunos',
        where: 'facial = ? OR facial IS NULL',
        whereArgs: ['NAO']
    );
  }

  // ========================================================================
  // FIM DA CORREÇÃO
  // ========================================================================


  Future<Map<String, dynamic>?> getAlunoByCpf(String cpf) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'alunos',
      where: 'cpf = ?',
      whereArgs: [cpf],
    );
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<void> updateAlunoFacial(String cpf, String status) async {
    final db = await database;
    await db.update(
      'alunos',
      {'facial': status},
      where: 'cpf = ?',
      whereArgs: [cpf],
    );
  }

  // Métodos para embeddings
  Future<void> insertEmbedding(Map<String, dynamic> embedding) async {
    final db = await database;
    await db.insert(
      'embeddings',
      {
        ...embedding,
        'embedding': jsonEncode(embedding['embedding']),
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllEmbeddings() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('embeddings');

    return maps.map((map) {
      return {
        ...map,
        'embedding': jsonDecode(map['embedding']),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getTodosAlunosComFacial() async {
    final db = await database;

    // ✅ CORREÇÃO: Buscar APENAS da tabela pessoas_facial (fonte única da verdade)
    // Removido UNION desnecessário - pessoas_facial já contém tudo
    final List<Map<String, dynamic>> pessoasComFacial = await db.rawQuery('''
      SELECT cpf, nome, email, telefone, turma, embedding, movimentacao, inicio_viagem, fim_viagem
      FROM pessoas_facial
      WHERE facial_status = 'CADASTRADA' AND embedding IS NOT NULL
    ''');

    return pessoasComFacial.map((pessoa) {
      return {
        ...pessoa,
        'embedding': jsonDecode(pessoa['embedding']),
      };
    }).toList();
  }

  Future<void> updatePessoaMovimentacao(
      String cpf, String movimentacao) async {
    if (cpf.isEmpty) return;
    final db = await database;
    await db.update(
      'pessoas_facial',
      {
        'movimentacao': movimentacao,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'cpf = ?',
      whereArgs: [cpf],
    );
  }

  Future<Map<String, int>> getContagemPorMovimentacao() async {
    final db = await database;

    // ✅ Buscar da tabela pessoas_facial (onde as pessoas ESTÃO AGORA)
    // Não dos logs (histórico), para ser consistente com a listagem
    final result = await db.rawQuery('''
    SELECT TRIM(UPPER(movimentacao)) AS tipo,
           COUNT(*) AS total
    FROM pessoas_facial
    WHERE UPPER(TRIM(movimentacao)) IN ('QUARTO', 'PISCINA', 'BALADA')
    GROUP BY TRIM(UPPER(movimentacao))
    ORDER BY
      CASE TRIM(UPPER(movimentacao))
        WHEN 'QUARTO' THEN 1
        WHEN 'PISCINA' THEN 2
        WHEN 'BALADA' THEN 3
        ELSE 4
      END
  ''');

    final mapa = <String, int>{
      'QUARTO': 0,
      'PISCINA': 0,
      'BALADA': 0,
    };

    for (final row in result) {
      final chave = (row['tipo'] as String?) ?? '';
      if (chave.isNotEmpty && mapa.containsKey(chave)) {
        mapa[chave] = (row['total'] as int?) ?? 0;
      }
    }

    return mapa;
  }

  // ✅ CORREÇÃO: Método insertLog sem parâmetro timestamp
  Future<void> insertLog({
    required String cpf,
    required String personName,
    required DateTime timestamp,
    required double confidence,
    required String tipo,
    String? operadorNome,
    String? inicioViagem,
    String? fimViagem,
  }) async {
    final db = await database;
    // ✅ CORREÇÃO: Adicionar conflictAlgorithm.ignore para evitar duplicatas
    // Devido à UNIQUE constraint (cpf, timestamp, tipo), se houver tentativa de inserir
    // um log duplicado, ele será simplesmente ignorado ao invés de dar erro
    await db.insert(
      'logs',
      {
        'cpf': cpf,
        'person_name': personName,
        'timestamp': timestamp.toIso8601String(),
        'confidence': confidence,
        'tipo': tipo,
        'operador_nome': operadorNome,
        'inicio_viagem': inicioViagem,
        'fim_viagem': fimViagem,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    final tipoNormalizado = tipo.trim().toUpperCase();
    if (tipoNormalizado.isNotEmpty &&
        tipoNormalizado != 'RECONHECIMENTO' &&
        tipoNormalizado != 'FACIAL') {
      await updatePessoaMovimentacao(cpf, tipoNormalizado);
    }
  }

  Future<List<Map<String, dynamic>>> getLogsHoje() async {
    final db = await database;
    final hoje = DateTime.now();
    final inicioDia = DateTime(hoje.year, hoje.month, hoje.day);

    return await db.query(
      'logs',
      where: 'timestamp >= ?',
      whereArgs: [inicioDia.toIso8601String()],
      orderBy: 'timestamp DESC',
    );
  }

  // ✅ CORREÇÃO: Métodos para sincronização
  Future<void> enqueueOutbox(String tipo, Map<String, dynamic> payload) async {
    final db = await database;
    await db.insert('sync_queue', {
      'tipo': tipo,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getOutboxBatch({int limit = 50}) async {
    final db = await database;
    return await db.query(
      'sync_queue',
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  Future<void> deleteOutboxIds(List<int> ids) async {
    final db = await database;
    if (ids.isEmpty) return;

    await db.delete(
      'sync_queue',
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  // Métodos para painel administrativo
  Future<List<Map<String, dynamic>>> getAllLogs() async {
    final db = await database;
    return await db.query('logs', orderBy: 'timestamp DESC');
  }

  /// Retorna logs apenas do operador especificado
  Future<List<Map<String, dynamic>>> getLogsByOperador(String operadorNome) async {
    final db = await database;
    return await db.query(
      'logs',
      where: 'operador_nome = ?',
      whereArgs: [operadorNome],
      orderBy: 'timestamp DESC',
    );
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('passageiros');
    await db.delete('alunos');
    await db.delete('embeddings');
    await db.delete('logs');
    await db.delete('sync_queue');
    // NÃO deletar usuarios para manter login offline
    print('✅ Todos os dados foram limpos do banco de dados');
  }

  // ========================================================================
  // MÉTODOS PARA USUÁRIOS (LOGIN OFFLINE)
  // ========================================================================

  Future<void> upsertUsuario(Map<String, dynamic> usuario) async {
    final db = await database;
    await db.insert(
      'usuarios',
      {
        ...usuario,
        'updated_at': DateTime.now().toIso8601String(),
        'created_at': usuario['created_at'] ?? DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getUsuarioByCpf(String cpf) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'usuarios',
      where: 'cpf = ? AND ativo = 1',
      whereArgs: [cpf],
    );
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllUsuarios() async {
    final db = await database;
    return await db.query('usuarios', where: 'ativo = 1');
  }

  Future<int> getTotalUsuarios() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM usuarios WHERE ativo = 1');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> deleteAllUsuarios() async {
    final db = await database;
    await db.delete('usuarios');
    print('✅ Todos os usuários foram deletados');
  }

  // ========================================================================
  // MÉTODOS PARA PESSOAS_FACIAL (Reconhecimento Facial)
  // ========================================================================

  /// Insere ou atualiza uma pessoa com facial cadastrada
  Future<void> upsertPessoaFacial(Map<String, dynamic> pessoa) async {
    final db = await database;
    final data = Map<String, dynamic>.from(pessoa);
    data['updated_at'] = DateTime.now().toIso8601String();
    data['created_at'] =
        pessoa['created_at'] ?? DateTime.now().toIso8601String();

    if (!data.containsKey('movimentacao')) {
      final existente = await db.query(
        'pessoas_facial',
        columns: ['movimentacao'],
        where: 'cpf = ?',
        whereArgs: [data['cpf']],
        limit: 1,
      );
      if (existente.isNotEmpty) {
        data['movimentacao'] = existente.first['movimentacao'];
      } else {
        data['movimentacao'] = '';
      }
    }

    await db.insert(
      'pessoas_facial',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Busca todas as pessoas com facial cadastrada
  Future<List<Map<String, dynamic>>> getAllPessoasFacial() async {
    final db = await database;
    final List<Map<String, dynamic>> pessoas = await db.query('pessoas_facial');

    // Decodificar embeddings
    return pessoas.map((pessoa) {
      if (pessoa['embedding'] != null && pessoa['embedding'] != '') {
        return {
          ...pessoa,
          'embedding': jsonDecode(pessoa['embedding']),
        };
      }
      return pessoa;
    }).toList();
  }

  /// Busca uma pessoa por CPF
  Future<Map<String, dynamic>?> getPessoaFacialByCpf(String cpf) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'pessoas_facial',
      where: 'cpf = ?',
      whereArgs: [cpf],
    );

    if (maps.isEmpty) return null;

    final pessoa = maps.first;
    if (pessoa['embedding'] != null && pessoa['embedding'] != '') {
      pessoa['embedding'] = jsonDecode(pessoa['embedding']);
    }
    return pessoa;
  }

  /// Deleta uma pessoa facial por CPF
  Future<void> deletePessoaFacial(String cpf) async {
    final db = await database;
    await db.delete(
      'pessoas_facial',
      where: 'cpf = ?',
      whereArgs: [cpf],
    );
  }

  /// Conta total de pessoas com facial
  Future<int> getTotalPessoasFacial() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM pessoas_facial');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}