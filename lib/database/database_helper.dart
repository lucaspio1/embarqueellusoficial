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
      version: 10, // ✅ VERSÃO 10: REFATORAÇÃO - Unificar alunos + pessoas_facial, remover embeddings e passageiros
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
    if (oldVersion < 5) {
      // Adicionar coluna colegio às tabelas
      try {
        await db.execute("ALTER TABLE pessoas_facial ADD COLUMN colegio TEXT");
        print('✅ [DB] Migração v4 -> v5: Adicionada coluna colegio em pessoas_facial');
      } catch (e) {
        print('⚠️ [DB] Coluna colegio já existia em pessoas_facial: $e');
      }

      try {
        await db.execute("ALTER TABLE alunos ADD COLUMN colegio TEXT");
        print('✅ [DB] Migração v4 -> v5: Adicionada coluna colegio em alunos');
      } catch (e) {
        print('⚠️ [DB] Coluna colegio já existia em alunos: $e');
      }

      try {
        await db.execute("ALTER TABLE logs ADD COLUMN colegio TEXT");
        print('✅ [DB] Migração v4 -> v5: Adicionada coluna colegio em logs');
      } catch (e) {
        print('⚠️ [DB] Coluna colegio já existia em logs: $e');
      }

      try {
        await db.execute("ALTER TABLE passageiros ADD COLUMN colegio TEXT");
        print('✅ [DB] Migração v4 -> v5: Adicionada coluna colegio em passageiros');
      } catch (e) {
        print('⚠️ [DB] Coluna colegio já existia em passageiros: $e');
      }
    }
    if (oldVersion < 6) {
      // Adicionar coluna turma às tabelas
      try {
        await db.execute("ALTER TABLE pessoas_facial ADD COLUMN turma TEXT");
        print('✅ [DB] Migração v5 -> v6: Adicionada coluna turma em pessoas_facial');
      } catch (e) {
        print('⚠️ [DB] Coluna turma já existia em pessoas_facial: $e');
      }

      try {
        await db.execute("ALTER TABLE alunos ADD COLUMN turma TEXT");
        print('✅ [DB] Migração v5 -> v6: Adicionada coluna turma em alunos');
      } catch (e) {
        print('⚠️ [DB] Coluna turma já existia em alunos: $e');
      }

      try {
        await db.execute("ALTER TABLE logs ADD COLUMN turma TEXT");
        print('✅ [DB] Migração v5 -> v6: Adicionada coluna turma em logs');
      } catch (e) {
        print('⚠️ [DB] Coluna turma já existia em logs: $e');
      }

      try {
        await db.execute("ALTER TABLE passageiros ADD COLUMN turma TEXT");
        print('✅ [DB] Migração v5 -> v6: Adicionada coluna turma em passageiros');
      } catch (e) {
        print('⚠️ [DB] Coluna turma já existia em passageiros: $e');
      }
    }
    if (oldVersion < 7) {
      // Adicionar tabela quartos
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS quartos(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            numero_quarto TEXT NOT NULL,
            escola TEXT,
            nome_hospede TEXT NOT NULL,
            cpf TEXT NOT NULL,
            inicio_viagem TEXT,
            fim_viagem TEXT
          )
        ''');
        print('✅ [DB] Migração v6 -> v7: Tabela quartos criada');
      } catch (e) {
        print('⚠️ [DB] Erro ao criar tabela quartos: $e');
      }
    }
    if (oldVersion < 8) {
      // Adicionar índices para otimização de performance
      try {
        // Índice em pessoas_facial.cpf - usado em joins e buscas
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pessoas_cpf ON pessoas_facial(cpf)');
        print('✅ [DB] Migração v7 -> v8: Índice idx_pessoas_cpf criado');
      } catch (e) {
        print('⚠️ [DB] Erro ao criar idx_pessoas_cpf: $e');
      }

      try {
        // Índice composto em logs(cpf, timestamp) - usado em queries de histórico
        await db.execute('CREATE INDEX IF NOT EXISTS idx_logs_cpf_timestamp ON logs(cpf, timestamp)');
        print('✅ [DB] Migração v7 -> v8: Índice idx_logs_cpf_timestamp criado');
      } catch (e) {
        print('⚠️ [DB] Erro ao criar idx_logs_cpf_timestamp: $e');
      }

      try {
        // Índice em pessoas_facial.movimentacao - usado em filtros de localização
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pessoas_movimentacao ON pessoas_facial(movimentacao)');
        print('✅ [DB] Migração v7 -> v8: Índice idx_pessoas_movimentacao criado');
      } catch (e) {
        print('⚠️ [DB] Erro ao criar idx_pessoas_movimentacao: $e');
      }

      try {
        // Índice em logs.tipo - usado em filtros de tipo de movimentação
        await db.execute('CREATE INDEX IF NOT EXISTS idx_logs_tipo ON logs(tipo)');
        print('✅ [DB] Migração v7 -> v8: Índice idx_logs_tipo criado');
      } catch (e) {
        print('⚠️ [DB] Erro ao criar idx_logs_tipo: $e');
      }

      try {
        // Índice em pessoas_facial.facial_status - usado em filtros de status
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pessoas_facial_status ON pessoas_facial(facial_status)');
        print('✅ [DB] Migração v7 -> v8: Índice idx_pessoas_facial_status criado');
      } catch (e) {
        print('⚠️ [DB] Erro ao criar idx_pessoas_facial_status: $e');
      }

      try {
        // Índice em quartos.cpf - usado em joins com pessoas_facial
        await db.execute('CREATE INDEX IF NOT EXISTS idx_quartos_cpf ON quartos(cpf)');
        print('✅ [DB] Migração v7 -> v8: Índice idx_quartos_cpf criado');
      } catch (e) {
        print('⚠️ [DB] Erro ao criar idx_quartos_cpf: $e');
      }

      try {
        // Índice em alunos.cpf - usado em buscas e joins
        await db.execute('CREATE INDEX IF NOT EXISTS idx_alunos_cpf ON alunos(cpf)');
        print('✅ [DB] Migração v7 -> v8: Índice idx_alunos_cpf criado');
      } catch (e) {
        print('⚠️ [DB] Erro ao criar idx_alunos_cpf: $e');
      }
    }
    if (oldVersion < 9) {
      // Adicionar coluna sincronizado à tabela logs para controle de sincronização
      try {
        await db.execute('ALTER TABLE logs ADD COLUMN sincronizado INTEGER DEFAULT 0');
        print('✅ [DB] Migração v8 -> v9: Adicionada coluna sincronizado na tabela logs');
      } catch (e) {
        print('⚠️ [DB] Coluna sincronizado já existia em logs: $e');
      }

      try {
        // Índice em logs.sincronizado - usado para buscar logs pendentes de sincronização
        await db.execute('CREATE INDEX IF NOT EXISTS idx_logs_sincronizado ON logs(sincronizado)');
        print('✅ [DB] Migração v8 -> v9: Índice idx_logs_sincronizado criado');
      } catch (e) {
        print('⚠️ [DB] Erro ao criar idx_logs_sincronizado: $e');
      }
    }

    if (oldVersion < 10) {
      print('🔄 [DB] Iniciando migração v9 -> v10: REFATORAÇÃO COMPLETA');

      // ============================================
      // FASE 1: Adicionar novos campos em alunos
      // ============================================
      try {
        await db.execute('ALTER TABLE alunos ADD COLUMN embedding TEXT');
        await db.execute('ALTER TABLE alunos ADD COLUMN facial_cadastrada INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE alunos ADD COLUMN data_cadastro_facial TEXT');
        await db.execute('ALTER TABLE alunos ADD COLUMN embarcado INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE alunos ADD COLUMN data_embarque TEXT');
        await db.execute('ALTER TABLE alunos ADD COLUMN retornado INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE alunos ADD COLUMN data_retorno TEXT');
        await db.execute('ALTER TABLE alunos ADD COLUMN movimentacao TEXT DEFAULT "QUARTO"');
        await db.execute('ALTER TABLE alunos ADD COLUMN onibus TEXT');
        await db.execute('ALTER TABLE alunos ADD COLUMN codigo_pulseira TEXT');
        await db.execute('ALTER TABLE alunos ADD COLUMN id_passeio TEXT');
        await db.execute('ALTER TABLE alunos ADD COLUMN updated_at TEXT');
        print('✅ [DB] Novos campos adicionados à tabela alunos');
      } catch (e) {
        print('⚠️ [DB] Erro ao adicionar campos em alunos: $e');
      }

      // ============================================
      // FASE 2: Migrar dados de pessoas_facial → alunos (se existirem)
      // ============================================
      try {
        // Verificar se pessoas_facial existe e tem dados
        final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM pessoas_facial');
        final count = Sqflite.firstIntValue(countResult) ?? 0;

        if (count > 0) {
          print('📦 [DB] Migrando $count registros de pessoas_facial → alunos');

          // Atualizar alunos existentes com dados de pessoas_facial
          await db.execute('''
            UPDATE alunos
            SET
              embedding = (SELECT embedding FROM pessoas_facial WHERE pessoas_facial.cpf = alunos.cpf),
              facial_cadastrada = 1,
              movimentacao = (SELECT movimentacao FROM pessoas_facial WHERE pessoas_facial.cpf = alunos.cpf),
              updated_at = (SELECT updated_at FROM pessoas_facial WHERE pessoas_facial.cpf = alunos.cpf)
            WHERE cpf IN (SELECT cpf FROM pessoas_facial)
          ''');

          // Inserir pessoas_facial que não existem em alunos
          await db.execute('''
            INSERT OR IGNORE INTO alunos (cpf, nome, colegio, email, telefone, turma, embedding, facial_cadastrada, movimentacao, inicio_viagem, fim_viagem, created_at, updated_at)
            SELECT cpf, nome, colegio, email, telefone, turma, embedding, 1, movimentacao, inicio_viagem, fim_viagem, created_at, updated_at
            FROM pessoas_facial
          ''');

          print('✅ [DB] Dados migrados de pessoas_facial → alunos');
        }
      } catch (e) {
        print('⚠️ [DB] Erro ao migrar pessoas_facial: $e');
      }

      // ============================================
      // FASE 3: Migrar dados de passageiros → alunos (se existirem)
      // ============================================
      try {
        final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM passageiros');
        final count = Sqflite.firstIntValue(countResult) ?? 0;

        if (count > 0) {
          print('📦 [DB] Migrando $count registros de passageiros → alunos');

          await db.execute('''
            UPDATE alunos
            SET
              embarcado = CASE WHEN (SELECT embarque FROM passageiros WHERE passageiros.cpf = alunos.cpf) = 'SIM' THEN 1 ELSE 0 END,
              retornado = CASE WHEN (SELECT retorno FROM passageiros WHERE passageiros.cpf = alunos.cpf) = 'SIM' THEN 1 ELSE 0 END,
              onibus = (SELECT onibus FROM passageiros WHERE passageiros.cpf = alunos.cpf),
              codigo_pulseira = (SELECT codigo_pulseira FROM passageiros WHERE passageiros.cpf = alunos.cpf),
              id_passeio = (SELECT id_passeio FROM passageiros WHERE passageiros.cpf = alunos.cpf)
            WHERE cpf IN (SELECT cpf FROM passageiros WHERE cpf IS NOT NULL)
          ''');

          print('✅ [DB] Dados migrados de passageiros → alunos');
        }
      } catch (e) {
        print('⚠️ [DB] Erro ao migrar passageiros: $e');
      }

      // ============================================
      // FASE 4: Dropar tabelas antigas
      // ============================================
      try {
        await db.execute('DROP TABLE IF EXISTS pessoas_facial');
        print('✅ [DB] Tabela pessoas_facial removida');
      } catch (e) {
        print('⚠️ [DB] Erro ao remover pessoas_facial: $e');
      }

      try {
        await db.execute('DROP TABLE IF EXISTS embeddings');
        print('✅ [DB] Tabela embeddings removida');
      } catch (e) {
        print('⚠️ [DB] Erro ao remover embeddings: $e');
      }

      try {
        await db.execute('DROP TABLE IF EXISTS passageiros');
        print('✅ [DB] Tabela passageiros removida');
      } catch (e) {
        print('⚠️ [DB] Erro ao remover passageiros: $e');
      }

      // ============================================
      // FASE 5: Criar índices otimizados
      // ============================================
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_alunos_facial_cadastrada ON alunos(facial_cadastrada)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_alunos_embarcado ON alunos(embarcado)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_alunos_movimentacao ON alunos(movimentacao)');
        print('✅ [DB] Índices otimizados criados em alunos');
      } catch (e) {
        print('⚠️ [DB] Erro ao criar índices: $e');
      }

      print('✅ [DB] Migração v9 -> v10 concluída com sucesso!');
    }
  }

  Future<void> _createDatabase(Database db, int version) async {
    // ============================================
    // TABELA UNIFICADA: ALUNOS
    // ============================================
    await db.execute('''
      CREATE TABLE alunos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cpf TEXT UNIQUE,
        nome TEXT,
        colegio TEXT,
        email TEXT,
        telefone TEXT,
        turma TEXT,

        -- Facial
        embedding TEXT,
        facial_cadastrada INTEGER DEFAULT 0,
        data_cadastro_facial TEXT,

        -- Embarque/Retorno
        embarcado INTEGER DEFAULT 0,
        data_embarque TEXT,
        retornado INTEGER DEFAULT 0,
        data_retorno TEXT,
        onibus TEXT,
        codigo_pulseira TEXT,
        id_passeio TEXT,

        -- Movimentação
        movimentacao TEXT DEFAULT 'QUARTO',

        -- QR Code (legado)
        tem_qr TEXT DEFAULT 'NAO',

        -- Viagem
        inicio_viagem TEXT,
        fim_viagem TEXT,

        -- Metadados
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cpf TEXT,
        person_name TEXT,
        colegio TEXT,
        turma TEXT,
        timestamp TEXT,
        confidence REAL,
        tipo TEXT,
        operador_nome TEXT,
        created_at TEXT,
        inicio_viagem TEXT,
        fim_viagem TEXT,
        sincronizado INTEGER DEFAULT 0,
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

    await db.execute('''
      CREATE TABLE quartos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        numero_quarto TEXT NOT NULL,
        escola TEXT,
        nome_hospede TEXT NOT NULL,
        cpf TEXT NOT NULL,
        inicio_viagem TEXT,
        fim_viagem TEXT
      )
    ''');

    // ✅ Criar índices para otimização de performance
    await db.execute('CREATE INDEX idx_alunos_cpf ON alunos(cpf)');
    await db.execute('CREATE INDEX idx_alunos_facial_cadastrada ON alunos(facial_cadastrada)');
    await db.execute('CREATE INDEX idx_alunos_embarcado ON alunos(embarcado)');
    await db.execute('CREATE INDEX idx_alunos_movimentacao ON alunos(movimentacao)');
    await db.execute('CREATE INDEX idx_logs_cpf_timestamp ON logs(cpf, timestamp)');
    await db.execute('CREATE INDEX idx_logs_tipo ON logs(tipo)');
    await db.execute('CREATE INDEX idx_logs_sincronizado ON logs(sincronizado)');
    await db.execute('CREATE INDEX idx_quartos_cpf ON quartos(cpf)');
    print('✅ [DB] Índices de performance criados');
  }

  Future<void> ensureFacialSchema() async {
    final db = await database;

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
      dynamic embedding;
      try {
        final embeddingStr = map['embedding'];
        if (embeddingStr != null && embeddingStr.toString().isNotEmpty) {
          final str = embeddingStr.toString();
          // Se não começa com '[', adiciona colchetes (formato CSV legado)
          final jsonStr = str.startsWith('[') ? str : '[$str]';
          embedding = jsonDecode(jsonStr);
        }
      } catch (e) {
        print('⚠️ [DB] Erro ao fazer parse de embedding: $e');
        embedding = null;
      }

      return {
        ...map,
        'embedding': embedding,
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
      dynamic embedding;
      try {
        final embeddingStr = pessoa['embedding']?.toString() ?? '';
        if (embeddingStr.isNotEmpty) {
          // Se não começa com '[', adiciona colchetes (formato CSV legado)
          final jsonStr = embeddingStr.startsWith('[')
              ? embeddingStr
              : '[$embeddingStr]';
          embedding = jsonDecode(jsonStr);
        }
      } catch (e) {
        print('⚠️ [DB] Erro ao fazer parse de embedding para ${pessoa['cpf']}: $e');
        embedding = null;
      }

      return {
        ...pessoa,
        'embedding': embedding,
      };
    }).toList();
  }

  /// Retorna alunos com facial ATIVOS (dentro do período de viagem)
  /// Filtra por data: hoje >= inicio_viagem E hoje <= fim_viagem
  Future<List<Map<String, dynamic>>> getTodosAlunosComFacialAtivos() async {
    final db = await database;
    final hoje = DateTime.now();

    // Buscar todas as pessoas com facial
    final List<Map<String, dynamic>> pessoasComFacial = await db.rawQuery('''
      SELECT cpf, nome, colegio, email, telefone, turma, embedding, movimentacao, inicio_viagem, fim_viagem
      FROM pessoas_facial
      WHERE facial_status = 'CADASTRADA' AND embedding IS NOT NULL
    ''');

    // 🔍 DEBUG: Log inicial
    print('🔍 [Filtro de Data] Total de pessoas com facial no banco: ${pessoasComFacial.length}');
    print('🔍 [Filtro de Data] Data de hoje: ${hoje.day.toString().padLeft(2, '0')}/${hoje.month.toString().padLeft(2, '0')}/${hoje.year}');

    // Filtrar no Dart por data (mais flexível para diferentes formatos)
    int pessoasSemData = 0;
    int pessoasBloqueadas = 0;
    int pessoasAtivas = 0;

    final resultadoFiltro = pessoasComFacial.where((pessoa) {
      final inicioStr = pessoa['inicio_viagem']?.toString() ?? '';
      final fimStr = pessoa['fim_viagem']?.toString() ?? '';

      // Se não tem datas, considera ativo (para compatibilidade)
      if (inicioStr.isEmpty || fimStr.isEmpty) {
        pessoasSemData++;
        return true;
      }

      try {
        // Tentar parsear data em formato ISO (YYYY-MM-DD) ou DD/MM/YYYY
        DateTime? inicio;
        DateTime? fim;

        // Formato ISO: YYYY-MM-DD
        if (inicioStr.contains('-')) {
          inicio = DateTime.parse(inicioStr);
          fim = DateTime.parse(fimStr);
        }
        // Formato brasileiro: DD/MM/YYYY
        else if (inicioStr.contains('/')) {
          final partesInicio = inicioStr.split('/');
          final partesFim = fimStr.split('/');

          if (partesInicio.length == 3 && partesFim.length == 3) {
            inicio = DateTime(
              int.parse(partesInicio[2]), // ano
              int.parse(partesInicio[1]), // mês
              int.parse(partesInicio[0]), // dia
            );
            fim = DateTime(
              int.parse(partesFim[2]), // ano
              int.parse(partesFim[1]), // mês
              int.parse(partesFim[0]), // dia
            );
          }
        }

        // Se conseguiu parsear, verificar se está no período
        if (inicio != null && fim != null) {
          final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);
          final inicioSemHora = DateTime(inicio.year, inicio.month, inicio.day);
          final fimSemHora = DateTime(fim.year, fim.month, fim.day);

          final estaAtivo = hojeSemHora.isAfter(inicioSemHora.subtract(Duration(days: 1))) &&
                            hojeSemHora.isBefore(fimSemHora.add(Duration(days: 1)));

          if (estaAtivo) {
            pessoasAtivas++;
          } else {
            pessoasBloqueadas++;
            print('⚠️ [Filtro de Data] BLOQUEADO: ${pessoa['nome']} (${pessoa['cpf']}) - Viagem: $inicioStr a $fimStr');
          }

          return estaAtivo;
        }

        // Se não conseguiu parsear, considera ativo
        pessoasSemData++;
        return true;
      } catch (e) {
        print('⚠️ Erro ao parsear datas para ${pessoa['nome']}: $e');
        pessoasSemData++;
        return true; // Em caso de erro, considera ativo
      }
    }).toList();

    // 🔍 DEBUG: Log final do filtro
    print('🔍 [Filtro de Data] RESULTADO:');
    print('   ✅ Pessoas ATIVAS (passaram no filtro): $pessoasAtivas');
    print('   ⏭️ Pessoas SEM DATA (aceitas automaticamente): $pessoasSemData');
    print('   ❌ Pessoas BLOQUEADAS por data: $pessoasBloqueadas');
    print('   📊 Total DISPONÍVEL no app: ${resultadoFiltro.length}');

    final resultado = resultadoFiltro.map((pessoa) {
      dynamic embedding;
      try {
        final embeddingStr = pessoa['embedding']?.toString() ?? '';
        if (embeddingStr.isNotEmpty) {
          // Se não começa com '[', adiciona colchetes (formato CSV legado)
          final jsonStr = embeddingStr.startsWith('[')
              ? embeddingStr
              : '[$embeddingStr]';
          embedding = jsonDecode(jsonStr);
        }
      } catch (e) {
        print('⚠️ [DB] Erro ao fazer parse de embedding para ${pessoa['cpf']}: $e');
        embedding = null;
      }

      return {
        ...pessoa,
        'embedding': embedding,
      };
    }).toList();

    // 🔍 DEBUG: Verificar se os alunos têm timestamps de viagem
    if (resultado.isNotEmpty) {
      final primeiroAluno = resultado.first;
      print('🔍 [DEBUG getTodosAlunosComFacialAtivos] Total de alunos ativos: ${resultado.length}');
      print('🔍 [DEBUG getTodosAlunosComFacialAtivos] Exemplo - ${primeiroAluno['nome']}:');
      print('   - inicio_viagem: ${primeiroAluno['inicio_viagem']} (${primeiroAluno['inicio_viagem']?.toString().isNotEmpty == true ? "PREENCHIDO" : "VAZIO"})');
      print('   - fim_viagem: ${primeiroAluno['fim_viagem']} (${primeiroAluno['fim_viagem']?.toString().isNotEmpty == true ? "PREENCHIDO" : "VAZIO"})');
    }

    return resultado;
  }

  /// Conta quantos passageiros de uma lista específica têm facial cadastrada
  /// Usado no controle de embarque para contar faciais apenas da lista atual
  Future<int> contarFaciaisDaListaEmbarque(List<String> cpfs) async {
    if (cpfs.isEmpty) return 0;

    final db = await database;
    final placeholders = cpfs.map((_) => '?').join(',');

    final result = await db.rawQuery('''
      SELECT COUNT(*) as total
      FROM pessoas_facial
      WHERE facial_status = 'CADASTRADA'
        AND embedding IS NOT NULL
        AND cpf IN ($placeholders)
    ''', cpfs);

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Retorna pessoas com facial cadastrada filtradas por lista de CPFs
  /// Usado na tela Gerenciar Alunos para marcar quais têm facial
  Future<List<Map<String, dynamic>>> getPessoasFaciaisPorCPFs(List<String> cpfs) async {
    if (cpfs.isEmpty) return [];

    final db = await database;
    final placeholders = cpfs.map((_) => '?').join(',');

    final result = await db.rawQuery('''
      SELECT cpf, nome, email, telefone, turma, movimentacao, inicio_viagem, fim_viagem
      FROM pessoas_facial
      WHERE facial_status = 'CADASTRADA'
        AND embedding IS NOT NULL
        AND cpf IN ($placeholders)
    ''', cpfs);

    return result;
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
    WHERE UPPER(TRIM(movimentacao)) IN ('QUARTO', 'SAIU_DO_QUARTO', 'VOLTOU_AO_QUARTO', 'FOI_PARA_BALADA')
    GROUP BY TRIM(UPPER(movimentacao))
    ORDER BY
      CASE TRIM(UPPER(movimentacao))
        WHEN 'QUARTO' THEN 1
        WHEN 'SAIU_DO_QUARTO' THEN 2
        WHEN 'VOLTOU_AO_QUARTO' THEN 3
        WHEN 'FOI_PARA_BALADA' THEN 4
        ELSE 5
      END
  ''');

    final mapa = <String, int>{
      'QUARTO': 0,
      'SAIU_DO_QUARTO': 0,
      'VOLTOU_AO_QUARTO': 0,
      'FOI_PARA_BALADA': 0,
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
    String? colegio,
    String? turma,
    String? inicioViagem,
    String? fimViagem,
    bool updateMovimentacao = true, // ✅ Controla se deve atualizar movimentacao
    int sincronizado = 0, // ✅ Controla se log já está sincronizado (históricos = 1, novos = 0)
  }) async {
    final db = await database;

    // 🔍 DEBUG: Verificar valores antes de inserir no banco
    print('🔍 [DEBUG insertLog] Inserindo log para $personName');
    print('🔍 [DEBUG insertLog] inicioViagem: $inicioViagem (${inicioViagem?.isNotEmpty == true ? "PREENCHIDO" : "VAZIO"})');
    print('🔍 [DEBUG insertLog] fimViagem: $fimViagem (${fimViagem?.isNotEmpty == true ? "PREENCHIDO" : "VAZIO"})');

    // ✅ CORREÇÃO: Adicionar conflictAlgorithm.ignore para evitar duplicatas
    // Devido à UNIQUE constraint (cpf, timestamp, tipo), se houver tentativa de inserir
    // um log duplicado, ele será simplesmente ignorado ao invés de dar erro
    await db.insert(
      'logs',
      {
        'cpf': cpf,
        'person_name': personName,
        'colegio': colegio,
        'turma': turma,
        'timestamp': timestamp.toIso8601String(),
        'confidence': confidence,
        'tipo': tipo,
        'operador_nome': operadorNome,
        'inicio_viagem': inicioViagem,
        'fim_viagem': fimViagem,
        'sincronizado': sincronizado, // ✅ Logs históricos = 1, novos = 0
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    print('✅ [DEBUG insertLog] Log salvo no banco local com sucesso');

    // ✅ CORREÇÃO: Só atualiza movimentacao se for um log NOVO (não histórico)
    // Quando sincronizando logs históricos do Google Sheets, não devemos
    // sobrescrever o status atual (da aba PESSOAS) com dados históricos (da aba LOGS)
    final tipoNormalizado = tipo.trim().toUpperCase();
    if (updateMovimentacao &&
        tipoNormalizado.isNotEmpty &&
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

  /// Busca logs de hoje filtrados por operador (para tela de reconhecimento facial)
  Future<List<Map<String, dynamic>>> getLogsHojePorOperador(String operadorNome) async {
    final db = await database;
    final hoje = DateTime.now();
    final inicioDia = DateTime(hoje.year, hoje.month, hoje.day);

    return await db.query(
      'logs',
      where: 'timestamp >= ? AND operador_nome = ?',
      whereArgs: [inicioDia.toIso8601String(), operadorNome],
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

  /// Limpa TODOS os dados de viagens (incluindo pessoas_facial)
  /// Usado quando o admin encerra TODAS as viagens
  Future<void> limparTodosDados() async {
    final db = await database;

    print('🧹 [DB] Limpando TODOS os dados de viagens...');

    await db.delete('passageiros');
    await db.delete('alunos');
    await db.delete('embeddings');
    await db.delete('pessoas_facial');
    await db.delete('logs');
    await db.delete('sync_queue');
    await db.delete('quartos');

    // NÃO deletar usuarios para manter login offline
    print('✅ [DB] Todos os dados de viagens foram limpos');
  }

  /// Limpa dados de uma viagem específica
  /// Usado quando o admin encerra uma viagem específica
  Future<void> limparDadosPorViagem(String inicioViagem, String fimViagem) async {
    final db = await database;

    print('🧹 [DB] Limpando dados da viagem: $inicioViagem a $fimViagem');

    int totalRemovidos = 0;

    // Limpar passageiros
    final passageirosRemovidos = await db.delete(
      'passageiros',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );
    totalRemovidos += passageirosRemovidos;
    print('   - Passageiros removidos: $passageirosRemovidos');

    // Limpar alunos
    final alunosRemovidos = await db.delete(
      'alunos',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );
    totalRemovidos += alunosRemovidos;
    print('   - Alunos removidos: $alunosRemovidos');

    // ✅ IMPORTANTE: Buscar CPFs ANTES de deletar pessoas_facial (para limpar embeddings)
    final cpfsViagem = await db.query(
      'pessoas_facial',
      columns: ['cpf'],
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );

    // Limpar pessoas_facial
    final pessoasRemovidas = await db.delete(
      'pessoas_facial',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );
    totalRemovidos += pessoasRemovidas;
    print('   - Pessoas removidas: $pessoasRemovidas');

    // Limpar embeddings (faciais) dos CPFs da viagem
    int embeddingsRemovidos = 0;
    for (final row in cpfsViagem) {
      final cpf = row['cpf'] as String?;
      if (cpf != null && cpf.isNotEmpty) {
        final removed = await db.delete(
          'embeddings',
          where: 'cpf = ?',
          whereArgs: [cpf],
        );
        embeddingsRemovidos += removed;
      }
    }
    totalRemovidos += embeddingsRemovidos;
    print('   - Embeddings removidos: $embeddingsRemovidos');

    // Limpar logs
    final logsRemovidos = await db.delete(
      'logs',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );
    totalRemovidos += logsRemovidos;
    print('   - Logs removidos: $logsRemovidos');

    // Limpar quartos
    final quartosRemovidos = await db.delete(
      'quartos',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );
    totalRemovidos += quartosRemovidos;
    print('   - Quartos removidos: $quartosRemovidos');

    // ✅ Limpar outbox/sync_queue para evitar enviar dados órfãos ao servidor
    // Nota: sync_queue não tem colunas inicio_viagem/fim_viagem, então limpamos TODA a fila
    final outboxRemovidos = await db.delete('sync_queue');
    totalRemovidos += outboxRemovidos;
    print('   - Outbox removidos: $outboxRemovidos');

    print('✅ [DB] Total de registros removidos: $totalRemovidos');
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
        print('🔍 [DB] ${data['nome']}: Preservando movimentação existente: "${data['movimentacao']}"');
      } else {
        data['movimentacao'] = '';
        print('🔍 [DB] ${data['nome']}: Pessoa nova, movimentação vazia');
      }
    } else {
      print('🔍 [DB] ${data['nome']}: Salvando com movimentacao: "${data['movimentacao']}"');
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
        try {
          final embeddingStr = pessoa['embedding'].toString();
          // Se não começa com '[', adiciona colchetes (formato CSV legado)
          final jsonStr = embeddingStr.startsWith('[')
              ? embeddingStr
              : '[$embeddingStr]';
          return {
            ...pessoa,
            'embedding': jsonDecode(jsonStr),
          };
        } catch (e) {
          print('⚠️ [DB] Erro ao fazer parse de embedding para ${pessoa['cpf']}: $e');
          return pessoa;
        }
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
      try {
        final embeddingStr = pessoa['embedding'].toString();
        // Se não começa com '[', adiciona colchetes (formato CSV legado)
        final jsonStr = embeddingStr.startsWith('[')
            ? embeddingStr
            : '[$embeddingStr]';
        pessoa['embedding'] = jsonDecode(jsonStr);
      } catch (e) {
        print('⚠️ [DB] Erro ao fazer parse de embedding para ${pessoa['cpf']}: $e');
      }
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

  // ========================================================================
  // MÉTODOS PARA QUARTOS
  // ========================================================================

  /// Insere ou atualiza quarto
  Future<void> upsertQuarto(Map<String, dynamic> quarto) async {
    final db = await database;
    await db.insert(
      'quartos',
      quarto,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Busca todos os quartos
  Future<List<Map<String, dynamic>>> getAllQuartos() async {
    final db = await database;
    return await db.query('quartos');
  }

  /// Busca quartos agrupados por número de quarto
  /// Retorna um Map onde a chave é o número do quarto e o valor é a lista de hóspedes
  Future<Map<String, List<Map<String, dynamic>>>> getQuartosAgrupados() async {
    final db = await database;
    final quartos = await db.query('quartos', orderBy: 'numero_quarto ASC, nome_hospede ASC');

    final Map<String, List<Map<String, dynamic>>> agrupados = {};

    for (final quarto in quartos) {
      final numeroQuarto = quarto['numero_quarto']?.toString() ?? '';
      if (numeroQuarto.isEmpty) continue;

      if (!agrupados.containsKey(numeroQuarto)) {
        agrupados[numeroQuarto] = [];
      }
      agrupados[numeroQuarto]!.add(quarto);
    }

    return agrupados;
  }

  /// Busca hóspedes de um quarto específico com informação de presença
  /// Cruza dados com a tabela pessoas_facial para verificar movimentação
  Future<List<Map<String, dynamic>>> getHospedesDoQuarto(String numeroQuarto) async {
    final db = await database;

    // JOIN entre quartos e pessoas_facial para pegar a movimentação atual
    // USANDO TRIM para garantir que espaços em branco não atrapalhem o JOIN
    final result = await db.rawQuery('''
      SELECT
        q.numero_quarto,
        q.escola,
        q.nome_hospede,
        q.cpf as cpf_quarto,
        q.inicio_viagem,
        q.fim_viagem,
        p.cpf as cpf_pessoa,
        COALESCE(p.movimentacao, '') as movimentacao
      FROM quartos q
      LEFT JOIN pessoas_facial p ON TRIM(q.cpf) = TRIM(p.cpf)
      WHERE q.numero_quarto = ?
      ORDER BY q.nome_hospede ASC
    ''', [numeroQuarto]);

    // 🔍 DIAGNÓSTICO: Ver o que está retornando do JOIN
    print('🔍 [JOIN] Quarto $numeroQuarto:');
    for (final row in result) {
      print('   ${row['nome_hospede']}: CPF_Q="${row['cpf_quarto']}" CPF_P="${row['cpf_pessoa']}" MOV="${row['movimentacao']}"');
    }

    return result;
  }

  /// Limpa todos os quartos
  Future<void> clearQuartos() async {
    final db = await database;
    await db.delete('quartos');
    print('✅ Todos os quartos foram limpos');
  }

  /// Limpa quartos de uma viagem específica
  Future<void> clearQuartosPorViagem(String inicioViagem, String fimViagem) async {
    final db = await database;
    final quartosRemovidos = await db.delete(
      'quartos',
      where: 'inicio_viagem = ? AND fim_viagem = ?',
      whereArgs: [inicioViagem, fimViagem],
    );
    print('✅ Quartos removidos: $quartosRemovidos');
  }

  // ========================================================================
  // MÉTODOS PARA SINCRONIZAÇÃO DE LOGS COM CHUNKING
  // ========================================================================

  /// Busca logs pendentes de sincronização (sincronizado = 0)
  /// Usa limit para implementar chunking (envio em lotes)
  Future<List<Map<String, dynamic>>> getLogsPendentes({int limit = 50}) async {
    final db = await database;
    return await db.query(
      'logs',
      where: 'sincronizado = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
      limit: limit,
    );
  }

  /// Marca logs como sincronizados (sincronizado = 1)
  Future<void> marcarLogsSincronizados(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.update(
      'logs',
      {'sincronizado': 1},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    print('✅ [DB] ${ids.length} logs marcados como sincronizados');
  }

  /// Limpa logs antigos (mais de 30 dias E sincronizados)
  /// Mantém o app leve, guardando histórico de apenas 30 dias
  Future<int> limparLogsAntigos({int diasRetencao = 30}) async {
    final db = await database;
    final dataLimite = DateTime.now().subtract(Duration(days: diasRetencao));
    final totalRemovidos = await db.delete(
      'logs',
      where: 'sincronizado = 1 AND timestamp < ?',
      whereArgs: [dataLimite.toIso8601String()],
    );
    if (totalRemovidos > 0) {
      print('🧹 [DB] $totalRemovidos logs antigos removidos (>$diasRetencao dias)');
    }
    return totalRemovidos;
  }

  /// Conta total de logs pendentes de sincronização
  Future<int> contarLogsPendentes() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM logs WHERE sincronizado = 0'
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}