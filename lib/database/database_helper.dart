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
      version: 1,
      onCreate: _createDatabase,
    );
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
        codigo_pulseira TEXT
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
        created_at TEXT
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
      CREATE TABLE logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cpf TEXT,
        person_name TEXT,
        timestamp TEXT,
        confidence REAL,
        tipo TEXT,
        created_at TEXT
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

  Future<List<Map<String, dynamic>>> getAlunosEmbarcadosParaCadastro() async {
    final db = await database;
    return await db.query('alunos');
  }

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

    final List<Map<String, dynamic>> alunosComFacial = await db.rawQuery('''
      SELECT a.*, e.embedding 
      FROM alunos a 
      INNER JOIN embeddings e ON a.cpf = e.cpf 
      WHERE a.facial = 'CADASTRADA'
    ''');

    return alunosComFacial.map((aluno) {
      return {
        ...aluno,
        'embedding': jsonDecode(aluno['embedding']),
      };
    }).toList();
  }

  // ✅ CORREÇÃO: Método insertLog sem parâmetro timestamp
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
      'person_name': personName,
      'timestamp': timestamp.toIso8601String(),
      'confidence': confidence,
      'tipo': tipo,
      'created_at': DateTime.now().toIso8601String(),
    });
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

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}