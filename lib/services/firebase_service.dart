// lib/services/firebase_service.dart
// Serviço principal de sincronização usando Firebase Firestore
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/models/evento.dart';

class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Timer? _syncTimer;
  bool _isSyncing = false;

  // ValueNotifier para que widgets possam observar o estado de sincronização
  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);

  // Referências das coleções
  CollectionReference get _usuariosCollection => _firestore.collection('usuarios');
  CollectionReference get _alunosCollection => _firestore.collection('alunos');
  CollectionReference get _pessoasCollection => _firestore.collection('pessoas');
  CollectionReference get _logsCollection => _firestore.collection('logs');
  CollectionReference get _quartosCollection => _firestore.collection('quartos');
  CollectionReference get _embarquesCollection => _firestore.collection('embarques');
  CollectionReference get _eventosCollection => _firestore.collection('eventos');

  void init() {
    _syncTimer?.cancel();

    // ✅ HABILITAR PERSISTÊNCIA OFFLINE DO FIRESTORE
    // Cache automático de dados para funcionar offline
    _firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Sincronização automática a cada 1 minuto (para sincronizar dados locais pendentes)
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      print('⏰ [FirebaseService] Timer de sincronização disparado');
      await trySyncInBackground();
    });

    print('✅ [FirebaseService] Sincronização automática iniciada');
    print('✅ [FirebaseService] Cache offline habilitado (UNLIMITED)');
    trySyncInBackground();

    // Iniciar listeners em tempo real
    _initRealtimeListeners();
  }

  void dispose() {
    _syncTimer?.cancel();
  }

  // =============================
  // HELPER: Campo case-insensitive
  // =============================

  /// Helper para ler campo do Firestore aceitando maiúsculo ou minúsculo
  dynamic _getField(Map<String, dynamic> data, String fieldName, [dynamic defaultValue]) {
    // Tenta minúsculo primeiro (padrão)
    if (data.containsKey(fieldName)) {
      return data[fieldName] ?? defaultValue;
    }
    // Tenta MAIÚSCULO
    final upperFieldName = fieldName.toUpperCase();
    if (data.containsKey(upperFieldName)) {
      return data[upperFieldName] ?? defaultValue;
    }
    // Tenta primeira letra maiúscula (ex: Nome, Cpf)
    final capitalizedFieldName = fieldName[0].toUpperCase() + fieldName.substring(1);
    if (data.containsKey(capitalizedFieldName)) {
      return data[capitalizedFieldName] ?? defaultValue;
    }
    return defaultValue;
  }

  /// Converte Timestamp do Firebase ou String para formato dd/MM/yyyy
  String _convertTimestampToDate(dynamic value) {
    if (value == null) return '';

    // Se já é uma string, retorna direto
    if (value is String) return value;

    // Se é Timestamp do Firestore
    if (value is Timestamp) {
      final date = value.toDate();
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }

    return '';
  }

  // =============================
  // LISTENERS EM TEMPO REAL
  // =============================

  void _initRealtimeListeners() {
    // Listener para usuários
    _usuariosCollection.snapshots().listen((snapshot) {
      _syncUsuariosFromSnapshot(snapshot);
    }, onError: (error) {
      print('❌ [FirebaseService] Erro no listener de usuários: $error');
      Sentry.captureException(error);
    });

    // Listener para alunos
    _alunosCollection.snapshots().listen((snapshot) {
      _syncAlunosFromSnapshot(snapshot);
    }, onError: (error) {
      print('❌ [FirebaseService] Erro no listener de alunos: $error');
      Sentry.captureException(error);
    });

    // Listener para pessoas
    _pessoasCollection.snapshots().listen((snapshot) {
      _syncPessoasFromSnapshot(snapshot);
    }, onError: (error) {
      print('❌ [FirebaseService] Erro no listener de pessoas: $error');
      Sentry.captureException(error);
    });

    // Listener para logs
    _logsCollection
        .orderBy('timestamp', descending: true)
        .limit(1000)
        .snapshots()
        .listen((snapshot) {
      _syncLogsFromSnapshot(snapshot);
    }, onError: (error) {
      print('❌ [FirebaseService] Erro no listener de logs: $error');
      Sentry.captureException(error);
    });

    // Listener para quartos
    _quartosCollection.snapshots().listen((snapshot) {
      _syncQuartosFromSnapshot(snapshot);
    }, onError: (error) {
      print('❌ [FirebaseService] Erro no listener de quartos: $error');
      Sentry.captureException(error);
    });

    // Listener para eventos
    _eventosCollection
        .where('processado', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      _processEventos(snapshot);
    }, onError: (error) {
      print('❌ [FirebaseService] Erro no listener de eventos: $error');
      Sentry.captureException(error);
    });

    print('✅ [FirebaseService] Listeners em tempo real iniciados');
  }

  // =============================
  // SINCRONIZAÇÃO DOS SNAPSHOTS
  // =============================

  Future<void> _syncUsuariosFromSnapshot(QuerySnapshot snapshot) async {
    try {
      final db = await _db.database;
      final batch = db.batch();

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // Aceita tanto 'senha_hash' (hash) quanto 'senha' (texto plano)
        final senhaArmazenada = _getField(data, 'senha_hash') ?? _getField(data, 'senha') ?? '';

        batch.insert(
          'usuarios',
          {
            'user_id': doc.id,
            'nome': _getField(data, 'nome', ''),
            'cpf': _getField(data, 'cpf', ''),
            'senha_hash': senhaArmazenada,
            'perfil': _getField(data, 'perfil', 'USUARIO'),
            'ativo': _getField(data, 'ativo', false) == true ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      print('✅ [FirebaseService] ${snapshot.docs.length} usuários sincronizados');
    } catch (e) {
      print('❌ [FirebaseService] Erro ao sincronizar usuários: $e');
      Sentry.captureException(e);
    }
  }

  Future<void> _syncAlunosFromSnapshot(QuerySnapshot snapshot) async {
    try {
      final db = await _db.database;
      final batch = db.batch();

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // Converter timestamps do Firebase para strings dd/MM/yyyy
        final inicioViagem = _convertTimestampToDate(_getField(data, 'inicio_viagem'));
        final fimViagem = _convertTimestampToDate(_getField(data, 'fim_viagem'));

        batch.insert(
          'alunos',
          {
            'cpf': _getField(data, 'cpf', ''),
            'nome': _getField(data, 'nome', ''),
            'colegio': _getField(data, 'colegio', ''),
            'turma': _getField(data, 'turma', ''),
            'email': _getField(data, 'email', ''),
            'telefone': _getField(data, 'telefone', ''),
            'facial_status': _getField(data, 'facial_status', 'NAO'),
            'tem_qr': _getField(data, 'tem_qr', false) == true ? 1 : 0,
            'inicio_viagem': inicioViagem,
            'fim_viagem': fimViagem,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      print('✅ [FirebaseService] ${snapshot.docs.length} alunos sincronizados');
    } catch (e) {
      print('❌ [FirebaseService] Erro ao sincronizar alunos: $e');
      Sentry.captureException(e);
    }
  }

  Future<void> _syncPessoasFromSnapshot(QuerySnapshot snapshot) async {
    try {
      final db = await _db.database;
      final batch = db.batch();

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // Extrair embedding (array de 512 floats)
        final embeddingData = _getField(data, 'embedding');
        final embeddingList = (embeddingData as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ?? [];

        // Converter timestamps
        final inicioViagem = _convertTimestampToDate(_getField(data, 'inicio_viagem'));
        final fimViagem = _convertTimestampToDate(_getField(data, 'fim_viagem'));

        batch.insert(
          'pessoas_facial',
          {
            'person_id': doc.id,
            'cpf': _getField(data, 'cpf', ''),
            'nome': _getField(data, 'nome', ''),
            'colegio': _getField(data, 'colegio', ''),
            'turma': _getField(data, 'turma', ''),
            'email': _getField(data, 'email', ''),
            'telefone': _getField(data, 'telefone', ''),
            'embedding': embeddingList.join(','),
            'facial_status': _getField(data, 'facial_status', 'CADASTRADA'),
            'movimentacao': _getField(data, 'movimentacao', 'QUARTO'),
            'inicio_viagem': inicioViagem,
            'fim_viagem': fimViagem,
            'updated_at': _getField(data, 'updated_at')?.toString() ?? DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      print('✅ [FirebaseService] ${snapshot.docs.length} pessoas sincronizadas');
    } catch (e) {
      print('❌ [FirebaseService] Erro ao sincronizar pessoas: $e');
      Sentry.captureException(e);
    }
  }

  Future<void> _syncLogsFromSnapshot(QuerySnapshot snapshot) async {
    try {
      final db = await _db.database;
      final batch = db.batch();

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        final timestampData = _getField(data, 'timestamp');
        final timestamp = (timestampData as Timestamp?)?.toDate() ?? DateTime.now();

        // Converter timestamps de viagem
        final inicioViagem = _convertTimestampToDate(_getField(data, 'inicio_viagem'));
        final fimViagem = _convertTimestampToDate(_getField(data, 'fim_viagem'));

        batch.insert(
          'logs',
          {
            'cpf': _getField(data, 'cpf', ''),
            'person_name': _getField(data, 'person_name', ''),
            'timestamp': timestamp.toIso8601String(),
            'confidence': (_getField(data, 'confidence') as num?)?.toDouble() ?? 0.0,
            'tipo': _getField(data, 'tipo', 'RECONHECIMENTO'),
            'operador_nome': _getField(data, 'operador_nome', ''),
            'colegio': _getField(data, 'colegio', ''),
            'turma': _getField(data, 'turma', ''),
            'inicio_viagem': inicioViagem,
            'fim_viagem': fimViagem,
            'sincronizado': 1, // Vem do Firebase, já está sincronizado
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      print('✅ [FirebaseService] ${snapshot.docs.length} logs sincronizados');
    } catch (e) {
      print('❌ [FirebaseService] Erro ao sincronizar logs: $e');
      Sentry.captureException(e);
    }
  }

  Future<void> _syncQuartosFromSnapshot(QuerySnapshot snapshot) async {
    try {
      final db = await _db.database;
      final batch = db.batch();

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // Converter timestamps
        final inicioViagem = _convertTimestampToDate(_getField(data, 'inicio_viagem'));
        final fimViagem = _convertTimestampToDate(_getField(data, 'fim_viagem'));

        batch.insert(
          'quartos',
          {
            'numero_quarto': _getField(data, 'numero_quarto', ''),
            'escola': _getField(data, 'escola', ''),
            'nome_hospede': _getField(data, 'nome_hospede', ''),
            'cpf': _getField(data, 'cpf', ''),
            'inicio_viagem': inicioViagem,
            'fim_viagem': fimViagem,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      print('✅ [FirebaseService] ${snapshot.docs.length} quartos sincronizados');
    } catch (e) {
      print('❌ [FirebaseService] Erro ao sincronizar quartos: $e');
      Sentry.captureException(e);
    }
  }

  Future<void> _processEventos(QuerySnapshot snapshot) async {
    for (var doc in snapshot.docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        final tipoEvento = data['tipo_evento'] as String?;

        if (tipoEvento == 'viagem_encerrada') {
          print('🔔 [FirebaseService] Evento: Viagem encerrada detectada');
          // Processar encerramento de viagem localmente se necessário
        }

        // Marcar como processado
        await doc.reference.update({'processado': true});
      } catch (e) {
        print('❌ [FirebaseService] Erro ao processar evento ${doc.id}: $e');
        Sentry.captureException(e);
      }
    }
  }

  // =============================
  // ENFILEIRAMENTO DE DADOS
  // =============================

  Future<void> queueLogAcesso({
    required String cpf,
    required String personName,
    required DateTime timestamp,
    required double confidence,
    required String personId,
    required String tipo,
    String? operadorNome,
    String? colegio,
    String? turma,
    String? inicioViagem,
    String? fimViagem,
  }) async {
    // Salvar localmente primeiro
    await _db.insertLog(
      cpf: cpf,
      personName: personName,
      timestamp: timestamp,
      confidence: confidence,
      tipo: tipo,
      operadorNome: operadorNome,
      colegio: colegio,
      turma: turma,
      inicioViagem: inicioViagem,
      fimViagem: fimViagem,
    );

    // Tentar enviar para Firebase
    try {
      await _logsCollection.add({
        'cpf': cpf,
        'person_name': personName,
        'timestamp': Timestamp.fromDate(timestamp),
        'confidence': confidence,
        'tipo': tipo,
        'operador_nome': operadorNome ?? '',
        'colegio': colegio ?? '',
        'turma': turma ?? '',
        'inicio_viagem': inicioViagem ?? '',
        'fim_viagem': fimViagem ?? '',
        'created_at': FieldValue.serverTimestamp(),
      });
      print('✅ [FirebaseService] Log enviado para Firebase: $personName - $tipo');
    } catch (e) {
      print('⚠️ [FirebaseService] Erro ao enviar log, ficará pendente: $e');
      // O log ficará marcado como não sincronizado e será enviado depois
    }
  }

  Future<void> queueCadastroFacial({
    required String cpf,
    required String nome,
    required String email,
    required String telefone,
    required List<double> embedding,
    required String personId,
    String? colegio,
    String? turma,
    String? inicioViagem,
    String? fimViagem,
  }) async {
    // Buscar movimentação atual da pessoa
    final db = await _db.database;
    final pessoaExistente = await db.query(
      'pessoas_facial',
      columns: ['movimentacao'],
      where: 'cpf = ?',
      whereArgs: [cpf],
      limit: 1,
    );

    final movimentacaoAtual = pessoaExistente.isNotEmpty
        ? (pessoaExistente.first['movimentacao']?.toString() ?? 'QUARTO')
        : 'QUARTO';

    // Tentar enviar para Firebase
    try {
      await _pessoasCollection.doc(cpf).set({
        'cpf': cpf,
        'nome': nome,
        'colegio': colegio ?? '',
        'turma': turma ?? '',
        'email': email,
        'telefone': telefone,
        'embedding': embedding,
        'facial_status': 'CADASTRADA',
        'movimentacao': movimentacaoAtual,
        'inicio_viagem': inicioViagem ?? '',
        'fim_viagem': fimViagem ?? '',
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ [FirebaseService] Cadastro facial enviado para Firebase: $nome');
    } catch (e) {
      print('⚠️ [FirebaseService] Erro ao enviar cadastro facial: $e');
      // Enfileirar para retry
      await _db.enqueueOutbox('face_register', {
        'cpf': cpf,
        'nome': nome,
        'colegio': colegio ?? '',
        'turma': turma ?? '',
        'email': email,
        'telefone': telefone,
        'embedding': embedding,
        'personId': personId,
        'movimentacao': movimentacaoAtual,
        'inicio_viagem': inicioViagem ?? '',
        'fim_viagem': fimViagem ?? '',
      });
    }
  }

  // =============================
  // SINCRONIZAÇÃO DE PENDÊNCIAS
  // =============================

  Future<void> trySyncInBackground() async {
    if (_isSyncing) {
      print('⏭️ [FirebaseService] Sincronização já em andamento, pulando');
      return;
    }

    _isSyncing = true;
    isSyncingNotifier.value = true;

    try {
      await _syncPendingLogs();
      await _syncPendingOutbox();
    } catch (e) {
      print('❌ [FirebaseService] Erro na sincronização em background: $e');
      Sentry.captureException(e);
    } finally {
      _isSyncing = false;
      isSyncingNotifier.value = false;
    }
  }

  Future<void> _syncPendingLogs() async {
    try {
      final db = await _db.database;
      final pendingLogs = await db.query(
        'logs',
        where: 'sincronizado = ?',
        whereArgs: [0],
        limit: 50,
      );

      if (pendingLogs.isEmpty) return;

      print('📤 [FirebaseService] Sincronizando ${pendingLogs.length} logs pendentes...');

      final batch = _firestore.batch();
      final syncedIds = <int>[];

      for (final log in pendingLogs) {
        final timestamp = DateTime.parse(log['timestamp'] as String);
        final docRef = _logsCollection.doc();

        batch.set(docRef, {
          'cpf': log['cpf'],
          'person_name': log['person_name'],
          'timestamp': Timestamp.fromDate(timestamp),
          'confidence': log['confidence'],
          'tipo': log['tipo'],
          'operador_nome': log['operador_nome'] ?? '',
          'colegio': log['colegio'] ?? '',
          'turma': log['turma'] ?? '',
          'inicio_viagem': log['inicio_viagem'] ?? '',
          'fim_viagem': log['fim_viagem'] ?? '',
          'created_at': FieldValue.serverTimestamp(),
        });

        syncedIds.add(log['id'] as int);
      }

      await batch.commit();

      // Marcar como sincronizados
      for (final id in syncedIds) {
        await db.update(
          'logs',
          {'sincronizado': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      print('✅ [FirebaseService] ${syncedIds.length} logs sincronizados com sucesso');
    } catch (e) {
      print('❌ [FirebaseService] Erro ao sincronizar logs pendentes: $e');
      Sentry.captureException(e);
    }
  }

  Future<void> _syncPendingOutbox() async {
    try {
      final batch = await _db.getOutboxBatch(limit: 50);
      if (batch.isEmpty) return;

      print('📤 [FirebaseService] Sincronizando ${batch.length} itens da outbox...');

      for (final row in batch) {
        try {
          final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
          final tipo = row['tipo'] as String;

          if (tipo == 'face_register') {
            await _pessoasCollection.doc(payload['cpf']).set({
              'cpf': payload['cpf'],
              'nome': payload['nome'],
              'colegio': payload['colegio'] ?? '',
              'turma': payload['turma'] ?? '',
              'email': payload['email'],
              'telefone': payload['telefone'],
              'embedding': payload['embedding'],
              'facial_status': 'CADASTRADA',
              'movimentacao': payload['movimentacao'] ?? 'QUARTO',
              'inicio_viagem': payload['inicio_viagem'] ?? '',
              'fim_viagem': payload['fim_viagem'] ?? '',
              'updated_at': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }

          // Remover da outbox (deletar da sync_queue)
          final db = await _db.database;
          await db.delete('sync_queue', where: 'id = ?', whereArgs: [row['id']]);
          print('✅ [FirebaseService] Item ${row['id']} sincronizado e removido da outbox');
        } catch (e) {
          print('❌ [FirebaseService] Erro ao sincronizar item ${row['id']}: $e');
        }
      }
    } catch (e) {
      print('❌ [FirebaseService] Erro ao sincronizar outbox: $e');
      Sentry.captureException(e);
    }
  }

  // =============================
  // OPERAÇÕES ADMINISTRATIVAS
  // =============================

  Future<void> encerrarViagem({String? inicioViagem, String? fimViagem}) async {
    try {
      final batch = _firestore.batch();

      if (inicioViagem != null && fimViagem != null) {
        // Encerrar viagem específica
        print('🔚 [FirebaseService] Encerrando viagem: $inicioViagem a $fimViagem');

        // Deletar alunos da viagem
        final alunosSnapshot = await _alunosCollection
            .where('inicio_viagem', isEqualTo: inicioViagem)
            .where('fim_viagem', isEqualTo: fimViagem)
            .get();
        for (var doc in alunosSnapshot.docs) {
          batch.delete(doc.reference);
        }

        // Deletar pessoas da viagem
        final pessoasSnapshot = await _pessoasCollection
            .where('inicio_viagem', isEqualTo: inicioViagem)
            .where('fim_viagem', isEqualTo: fimViagem)
            .get();
        for (var doc in pessoasSnapshot.docs) {
          batch.delete(doc.reference);
        }

        // Deletar logs da viagem
        final logsSnapshot = await _logsCollection
            .where('inicio_viagem', isEqualTo: inicioViagem)
            .where('fim_viagem', isEqualTo: fimViagem)
            .get();
        for (var doc in logsSnapshot.docs) {
          batch.delete(doc.reference);
        }
      } else {
        // Encerrar TODAS as viagens
        print('🔚 [FirebaseService] Encerrando TODAS as viagens');

        // Deletar todos os alunos
        final alunosSnapshot = await _alunosCollection.get();
        for (var doc in alunosSnapshot.docs) {
          batch.delete(doc.reference);
        }

        // Deletar todas as pessoas
        final pessoasSnapshot = await _pessoasCollection.get();
        for (var doc in pessoasSnapshot.docs) {
          batch.delete(doc.reference);
        }

        // Deletar todos os logs
        final logsSnapshot = await _logsCollection.get();
        for (var doc in logsSnapshot.docs) {
          batch.delete(doc.reference);
        }
      }

      await batch.commit();

      // Criar evento
      await _eventosCollection.add({
        'tipo_evento': 'viagem_encerrada',
        'inicio_viagem': inicioViagem ?? '',
        'fim_viagem': fimViagem ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'processado': false,
      });

      print('✅ [FirebaseService] Viagem encerrada com sucesso');
    } catch (e) {
      print('❌ [FirebaseService] Erro ao encerrar viagem: $e');
      Sentry.captureException(e);
      rethrow;
    }
  }

  Future<void> enviarTodosParaQuarto() async {
    try {
      final pessoasSnapshot = await _pessoasCollection.get();
      final batch = _firestore.batch();

      for (var doc in pessoasSnapshot.docs) {
        batch.update(doc.reference, {
          'movimentacao': 'QUARTO',
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      print('✅ [FirebaseService] Todas as pessoas enviadas para QUARTO');
    } catch (e) {
      print('❌ [FirebaseService] Erro ao enviar todos para quarto: $e');
      Sentry.captureException(e);
      rethrow;
    }
  }

  Future<List<Map<String, String>>> listarViagens() async {
    try {
      final alunosSnapshot = await _alunosCollection.get();
      final viagensSet = <String>{};

      for (var doc in alunosSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final inicio = data['inicio_viagem'] as String? ?? '';
        final fim = data['fim_viagem'] as String? ?? '';

        if (inicio.isNotEmpty && fim.isNotEmpty) {
          viagensSet.add('$inicio|$fim');
        }
      }

      return viagensSet.map((v) {
        final parts = v.split('|');
        return {
          'inicio_viagem': parts[0],
          'fim_viagem': parts[1],
        };
      }).toList();
    } catch (e) {
      print('❌ [FirebaseService] Erro ao listar viagens: $e');
      Sentry.captureException(e);
      return [];
    }
  }

  // =============================
  // OPERAÇÕES DE EMBARQUE
  // =============================

  Future<void> atualizarEmbarque({
    required String cpf,
    required String idPasseio,
    required String onibus,
    String? embarque,
    String? retorno,
  }) async {
    try {
      final docId = '${cpf}_${idPasseio}_$onibus';
      await _embarquesCollection.doc(docId).set({
        'cpf': cpf,
        'idPasseio': idPasseio,
        'onibus': onibus,
        if (embarque != null) 'embarque': embarque,
        if (retorno != null) 'retorno': retorno,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ [FirebaseService] Embarque atualizado: $cpf');
    } catch (e) {
      print('❌ [FirebaseService] Erro ao atualizar embarque: $e');
      Sentry.captureException(e);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> buscarEmbarques({
    required String idPasseio,
    String? onibus,
  }) async {
    try {
      Query query = _embarquesCollection.where('idPasseio', isEqualTo: idPasseio);

      if (onibus != null) {
        query = query.where('onibus', isEqualTo: onibus);
      }

      final snapshot = await query.get();
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
    } catch (e) {
      print('❌ [FirebaseService] Erro ao buscar embarques: $e');
      Sentry.captureException(e);
      return [];
    }
  }

  // =============================
  // UTILITÁRIOS
  // =============================

  Future<bool> _hasInternet() async {
    final c = await Connectivity().checkConnectivity();
    return c != ConnectivityResult.none;
  }
}
