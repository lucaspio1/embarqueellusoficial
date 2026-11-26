// lib/screens/cadastro_facial_viagem_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:embarqueellus/config/app_config.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/models/camera_mode.dart';
import 'package:embarqueellus/models/face_camera_options.dart';
import 'package:embarqueellus/models/face_camera_result.dart';
import 'package:embarqueellus/screens/unified_face_camera_screen.dart';
import 'package:embarqueellus/services/api_service.dart';
import 'package:embarqueellus/services/auth_service.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/firebase_service.dart';
import 'package:embarqueellus/widgets/sync_status_icon.dart';

enum _FiltroFacial { todos, pendentes, cadastrados }

/// Tela exclusiva para administradores (ADMIN):
/// Permite escolher uma viagem, baixar TODOS os alunos dela (inclusive para uso
/// offline, sem ser apagado pelo escopo do delta sync) e cadastrar/refazer a
/// facial de cada aluno.
class CadastroFacialViagemScreen extends StatefulWidget {
  const CadastroFacialViagemScreen({super.key});

  @override
  State<CadastroFacialViagemScreen> createState() =>
      _CadastroFacialViagemScreenState();
}

class _CadastroFacialViagemScreenState
    extends State<CadastroFacialViagemScreen> {
  static const String _prefViagemMeta = 'cadastro_facial_viagem_meta_v1';
  static const String _prefViagemAlunos = 'cadastro_facial_viagem_alunos_v1';

  final _api = ApiService.instance;
  final _auth = AuthService.instance;
  final _db = DatabaseHelper.instance;
  final _faceService = FaceRecognitionService.instance;

  final TextEditingController _buscaViagemController = TextEditingController();
  final TextEditingController _buscaAlunoController = TextEditingController();

  bool _verificandoAcesso = true;
  bool _ehAdmin = false;

  // Estado da seleção de viagem
  bool _exibirSelecaoViagem = true;
  bool _carregandoViagens = false;
  String? _erroViagens;
  List<Map<String, dynamic>> _viagens = [];
  bool _mostrarEncerradas = false;
  bool _apenasPernoite = false;

  // Estado da viagem baixada
  Map<String, dynamic>? _viagemSelecionada;
  List<Map<String, dynamic>> _alunosViagem = [];
  Set<String> _cpfsNaFilaUpload = {};
  bool _baixandoAlunos = false;
  bool _processandoFacial = false;

  // Filtros dos alunos
  _FiltroFacial _filtroFacial = _FiltroFacial.todos;
  String? _onibusSelecionado;

  @override
  void initState() {
    super.initState();
    _buscaViagemController.addListener(_onFiltroChanged);
    _buscaAlunoController.addListener(_onFiltroChanged);
    FirebaseService.instance.isSyncingNotifier.addListener(_onSyncChanged);
    _inicializar();
  }

  @override
  void dispose() {
    FirebaseService.instance.isSyncingNotifier.removeListener(_onSyncChanged);
    _buscaViagemController.removeListener(_onFiltroChanged);
    _buscaAlunoController.removeListener(_onFiltroChanged);
    _buscaViagemController.dispose();
    _buscaAlunoController.dispose();
    super.dispose();
  }

  void _onSyncChanged() {
    if (!FirebaseService.instance.isSyncingNotifier.value &&
        mounted &&
        _ehAdmin) {
      _atualizarStatusFilaLocal();
    }
  }

  Future<void> _atualizarStatusFilaLocal() async {
    final statusLocal = await _consultarStatusFaciaisLocais();
    if (!mounted) return;
    setState(() {
      _cpfsNaFilaUpload = statusLocal.pendentesFila;
    });
  }

  void _onFiltroChanged() {
    if (mounted) setState(() {});
  }

  String _limparCpf(dynamic valor) {
    final bruto = (valor ?? '').toString().trim();
    final digitos = bruto.replaceAll(RegExp(r'\D'), '');
    return digitos.isNotEmpty ? digitos : bruto;
  }

  String _hojeISO() {
    final agora = DateTime.now();
    final ano = agora.year.toString().padLeft(4, '0');
    final mes = agora.month.toString().padLeft(2, '0');
    final dia = agora.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }

  String _formatarDataBR(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return '--';
    final partes = s.split('T').first.split('-');
    if (partes.length == 3) {
      return '${partes[2]}/${partes[1]}/${partes[0]}';
    }
    return s;
  }

  String _formatarPeriodo(String? inicio, String? fim) {
    final i = _formatarDataBR(inicio);
    final f = _formatarDataBR(fim);
    if (f == '--' || i == f) return i;
    return '$i a $f';
  }

  String _formatarHoraIso(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final hora = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dia/$mes às $hora:$min';
  }

  Future<void> _inicializar() async {
    final usuario = await _auth.getUsuarioLogado();
    final isAdmin =
        usuario?['perfil']?.toString().toUpperCase() == 'ADMIN';

    if (!mounted) return;
    if (!isAdmin) {
      setState(() {
        _ehAdmin = false;
        _verificandoAcesso = false;
      });
      return;
    }

    setState(() {
      _ehAdmin = true;
      _verificandoAcesso = false;
    });

    // Pré-carrega o modelo ArcFace em background para agilizar o 1º cadastro
    _faceService.init().catchError((e) {
      print('⚠️ [CadastroFacialViagem] Erro ao pré-carregar ArcFace: $e');
    });

    final carregouLocal = await _carregarViagemLocal();
    if (!carregouLocal) {
      await _carregarViagensDoServidor();
    }
  }

  /// Lê CPFs com facial cadastrada no SQLite local e CPFs ainda na fila de envio.
  Future<({Set<String> faciaisLocais, Set<String> pendentesFila})>
      _consultarStatusFaciaisLocais() async {
    final faciaisLocais = <String>{};
    final pendentesFila = <String>{};

    try {
      final db = await _db.database;
      final rowsAlunos = await db.rawQuery('''
        SELECT cpf FROM alunos
        WHERE facial_cadastrada = 1
          AND embedding IS NOT NULL
          AND TRIM(embedding) != ''
      ''');
      for (final row in rowsAlunos) {
        final c = _limparCpf(row['cpf']);
        if (c.isNotEmpty) faciaisLocais.add(c);
      }

      final rowsQueue = await db.query(
        'sync_queue',
        columns: ['payload'],
        where: 'tipo = ?',
        whereArgs: ['face_register'],
      );
      for (final row in rowsQueue) {
        try {
          final payloadStr = row['payload'] as String?;
          if (payloadStr == null || payloadStr.isEmpty) continue;
          final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
          final c = _limparCpf(payload['cpf']);
          if (c.isNotEmpty) {
            faciaisLocais.add(c);
            pendentesFila.add(c);
          }
        } catch (_) {}
      }
    } catch (e) {
      print('⚠️ [CadastroFacialViagem] Erro ao consultar status locais: $e');
    }

    return (faciaisLocais: faciaisLocais, pendentesFila: pendentesFila);
  }

  /// Restaura viagem e lista de alunos baixados anteriormente (funciona offline).
  Future<bool> _carregarViagemLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final metaStr = prefs.getString(_prefViagemMeta);
      final alunosStr = prefs.getString(_prefViagemAlunos);

      if (metaStr == null || alunosStr == null) return false;

      final meta = Map<String, dynamic>.from(jsonDecode(metaStr) as Map);
      final decodedList = jsonDecode(alunosStr) as List;
      final alunos = decodedList
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final statusLocal = await _consultarStatusFaciaisLocais();
      for (final aluno in alunos) {
        final cpfChave = _limparCpf(aluno['cpf']);
        if (statusLocal.faciaisLocais.contains(cpfChave)) {
          aluno['facial_cadastrada'] = true;
        }
      }

      if (!mounted) return true;
      setState(() {
        _viagemSelecionada = meta;
        _alunosViagem = alunos;
        _cpfsNaFilaUpload = statusLocal.pendentesFila;
        _exibirSelecaoViagem = false;
        _onibusSelecionado = null;
      });
      return true;
    } catch (e) {
      print('⚠️ [CadastroFacialViagem] Erro ao restaurar viagem local: $e');
      return false;
    }
  }

  Future<void> _salvarViagemLocal(
    Map<String, dynamic> meta,
    List<Map<String, dynamic>> alunos,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefViagemMeta, jsonEncode(meta));
    await prefs.setString(_prefViagemAlunos, jsonEncode(alunos));
  }

  Future<void> _limparViagemLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefViagemMeta);
    await prefs.remove(_prefViagemAlunos);

    if (!mounted) return;
    setState(() {
      _viagemSelecionada = null;
      _alunosViagem = [];
      _onibusSelecionado = null;
      _filtroFacial = _FiltroFacial.todos;
      _buscaAlunoController.clear();
      _exibirSelecaoViagem = true;
    });
    await _carregarViagensDoServidor();
  }

  Future<void> _carregarViagensDoServidor() async {
    if (!mounted) return;
    setState(() {
      _carregandoViagens = true;
      _erroViagens = null;
    });

    try {
      final viagens = await _api.getViagensUnicas(hoje: _hojeISO());
      if (!mounted) return;
      setState(() {
        _viagens = viagens;
        _carregandoViagens = false;
      });
    } catch (e, stackTrace) {
      print('❌ [CadastroFacialViagem] Erro ao buscar viagens: $e');
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao carregar viagens em CadastroFacialViagemScreen',
        }),
      );
      if (!mounted) return;
      setState(() {
        _erroViagens =
            'Não foi possível carregar as viagens. Verifique sua conexão com a internet.';
        _carregandoViagens = false;
      });
    }
  }

  Future<void> _baixarAlunosDaViagem(Map<String, dynamic> viagem) async {
    final colegio = (viagem['colegio'] ?? '').toString().trim();
    final inicio = (viagem['inicio'] ?? '').toString().trim();
    final fim = (viagem['fim'] ?? '').toString().trim();

    if (colegio.isEmpty || inicio.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Viagem sem colégio ou data de início definida.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _baixandoAlunos = true);

    try {
      final alunosApi = await _api.getAlunosDaViagem(
        colegio: colegio,
        inicio: inicio,
      );

      final statusLocal = await _consultarStatusFaciaisLocais();

      final alunosNormalizados = <Map<String, dynamic>>[];
      for (final raw in alunosApi) {
        final cpfBruto = (raw['cpf'] ?? '').toString().trim();
        final cpfChave = _limparCpf(cpfBruto);
        if (cpfChave.isEmpty) continue;

        final jaTemFacial = raw['facial_cadastrada'] == true ||
            statusLocal.faciaisLocais.contains(cpfChave);

        alunosNormalizados.add({
          'cpf': cpfBruto,
          'nome': (raw['nome'] ?? 'Sem nome').toString().trim(),
          'colegio': colegio,
          'turma': (raw['turma'] ?? '').toString().trim(),
          'onibus': (raw['onibus'] ?? '').toString().trim(),
          'idPasseio': (raw['idPasseio'] ?? '').toString().trim(),
          'numero_quarto': (raw['numero_quarto'] ?? '').toString().trim(),
          'inicio_viagem': inicio,
          'fim_viagem': fim.isNotEmpty ? fim : inicio,
          'facial_cadastrada': jaTemFacial,
        });
      }

      alunosNormalizados.sort(
        (a, b) => (a['nome'] as String)
            .toLowerCase()
            .compareTo((b['nome'] as String).toLowerCase()),
      );

      final meta = <String, dynamic>{
        'chave': (viagem['chave'] ?? '$colegio|$inicio').toString(),
        'colegio': colegio,
        'inicio': inicio,
        'fim': fim.isNotEmpty ? fim : inicio,
        'pernoite': viagem['pernoite'] == true,
        'baixado_em': DateTime.now().toIso8601String(),
      };

      await _salvarViagemLocal(meta, alunosNormalizados);

      if (!mounted) return;
      setState(() {
        _viagemSelecionada = meta;
        _alunosViagem = alunosNormalizados;
        _cpfsNaFilaUpload = statusLocal.pendentesFila;
        _exibirSelecaoViagem = false;
        _baixandoAlunos = false;
        _onibusSelecionado = null;
        _filtroFacial = _FiltroFacial.todos;
        _buscaAlunoController.clear();
      });

      final totalCadastrados = alunosNormalizados
          .where((a) => a['facial_cadastrada'] == true)
          .length;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ ${alunosNormalizados.length} aluno(s) baixado(s) ($totalCadastrados com facial). Pronto para uso offline!',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, stackTrace) {
      print('❌ [CadastroFacialViagem] Erro ao baixar alunos da viagem: $e');
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao baixar alunos da viagem',
          'colegio': colegio,
          'inicio': inicio,
        }),
      );
      if (!mounted) return;
      setState(() => _baixandoAlunos = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao baixar alunos da viagem: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cadastrarFacial(Map<String, dynamic> aluno) async {
    if (_processandoFacial) return;

    bool dialogAberto = false;
    try {
      final cfg = AppConfig.instance;
      final nome = (aluno['nome'] ?? 'Aluno').toString();
      final cpf = (aluno['cpf'] ?? '').toString().trim();

      final result = await Navigator.push<FaceCameraResult>(
        context,
        MaterialPageRoute(
          builder: (_) => UnifiedFaceCameraScreen(
            mode: CameraMode.enrollmentAdvanced,
            options: FaceCameraOptions(
              useFrontCamera: cfg.useFrontCameraEnrollment,
              resolution: cfg.cameraResolutionPreset,
              showFaceGuide: cfg.showFaceGuide,
              captureCount: cfg.enrollmentBurstCount,
              burstDelay:
                  Duration(milliseconds: cfg.enrollmentBurstIntervalMs),
              title: 'Cadastrar $nome',
              subtitle:
                  'Vamos tirar ${cfg.enrollmentBurstCount} fotos para maior precisão',
              showCaptureCounter: true,
            ),
          ),
        ),
      );

      if (!mounted) return;
      if (result == null || !result.success) return;

      final List<img.Image> faces = (result.processedImages != null &&
              result.processedImages!.isNotEmpty)
          ? result.processedImages!
          : (result.firstProcessedImage != null
              ? <img.Image>[result.firstProcessedImage!]
              : <img.Image>[]);

      if (faces.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Nenhuma imagem de rosto foi capturada.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _processandoFacial = true);
      _mostrarProgresso('Processando ${faces.length} foto(s)...');
      dialogAberto = true;

      final embeddings = <List<double>>[];
      for (final face in faces) {
        final emb = await _faceService.extractEmbedding(face);
        embeddings.add(emb);
      }

      final rawAvg = List<double>.filled(embeddings[0].length, 0.0);
      for (final emb in embeddings) {
        for (int i = 0; i < emb.length; i++) {
          rawAvg[i] += emb[i] / embeddings.length;
        }
      }
      final embedding = _faceService.normalizeL2(rawAvg);

      await FirebaseService.instance.queueCadastroFacial(
        cpf: cpf,
        nome: nome,
        colegio: (aluno['colegio'] ?? '').toString(),
        turma: (aluno['turma'] ?? '').toString(),
        email: '',
        telefone: '',
        embedding: embedding,
        personId: cpf,
        inicioViagem: (aluno['inicio_viagem'] ?? '').toString(),
        fimViagem: (aluno['fim_viagem'] ?? '').toString(),
      );

      // Atualiza imediatamente o cache local da viagem baixada
      final cpfChave = _limparCpf(cpf);
      for (final item in _alunosViagem) {
        if (_limparCpf(item['cpf']) == cpfChave) {
          item['facial_cadastrada'] = true;
        }
      }
      if (_viagemSelecionada != null) {
        await _salvarViagemLocal(_viagemSelecionada!, _alunosViagem);
      }

      final statusLocal = await _consultarStatusFaciaisLocais();

      await Sentry.captureMessage(
        'Facial cadastrada via tela de viagem (ADMIN)',
        level: SentryLevel.info,
        withScope: (scope) {
          scope.setTag('screen', 'cadastro_facial_viagem');
          scope.setContexts('aluno', {
            'cpf': cpf,
            'nome': nome,
            'colegio': aluno['colegio'],
            'inicio_viagem': aluno['inicio_viagem'],
            'fotos_processadas': faces.length,
          });
        },
      );

      if (!mounted) return;
      if (dialogAberto && Navigator.canPop(context)) {
        Navigator.pop(context);
        dialogAberto = false;
      }

      setState(() {
        _cpfsNaFilaUpload = statusLocal.pendentesFila;
        _processandoFacial = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '✅ Facial cadastrada: $nome',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '🎯 ${faces.length} foto(s) processada(s) • Sincronizando com a nuvem',
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, stackTrace) {
      print('❌ [CadastroFacialViagem] Erro ao cadastrar facial: $e');
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao cadastrar facial em CadastroFacialViagemScreen',
          'aluno_cpf': aluno['cpf'],
          'aluno_nome': aluno['nome'],
        }),
      );

      if (!mounted) return;
      if (dialogAberto && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      setState(() => _processandoFacial = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao cadastrar facial: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _mostrarProgresso(String mensagem) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF4C643C)),
              const SizedBox(height: 20),
              Text(mensagem, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmarLimparViagem() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar viagem baixada?'),
        content: const Text(
          'A lista de alunos desta viagem será removida do cache desta tela. '
          'Faciais já cadastradas continuam salvas e na fila de sincronização.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (confirmar == true) {
      await _limparViagemLocal();
    }
  }

  List<Map<String, dynamic>> get _viagensFiltradas {
    final query = _buscaViagemController.text.trim().toLowerCase();
    return _viagens.where((v) {
      final situacao = (v['situacao'] ?? '').toString().toLowerCase();
      if (!_mostrarEncerradas && situacao == 'encerrada') return false;
      if (_apenasPernoite && v['pernoite'] != true) return false;
      if (query.isEmpty) return true;

      final colegio = (v['colegio'] ?? '').toString().toLowerCase();
      final inicio = (v['inicio'] ?? '').toString().toLowerCase();
      final inicioBr = _formatarDataBR(v['inicio']?.toString()).toLowerCase();
      final passeios = (v['passeios'] is List)
          ? (v['passeios'] as List).join(' ').toLowerCase()
          : '';
      return colegio.contains(query) ||
          inicio.contains(query) ||
          inicioBr.contains(query) ||
          passeios.contains(query);
    }).toList();
  }

  List<String> get _onibusDisponiveis {
    final set = <String>{};
    for (final a in _alunosViagem) {
      final bus = (a['onibus'] ?? '').toString().trim();
      if (bus.isNotEmpty) set.add(bus);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<Map<String, dynamic>> get _alunosFiltrados {
    final query = _buscaAlunoController.text.trim().toLowerCase();
    return _alunosViagem.where((a) {
      final temFacial = a['facial_cadastrada'] == true;
      if (_filtroFacial == _FiltroFacial.pendentes && temFacial) return false;
      if (_filtroFacial == _FiltroFacial.cadastrados && !temFacial) {
        return false;
      }

      if (_onibusSelecionado != null && _onibusSelecionado!.isNotEmpty) {
        if ((a['onibus'] ?? '').toString().trim() != _onibusSelecionado) {
          return false;
        }
      }

      if (query.isEmpty) return true;
      final nome = (a['nome'] ?? '').toString().toLowerCase();
      final cpf = (a['cpf'] ?? '').toString().toLowerCase();
      final cpfLimpo = _limparCpf(a['cpf']).toLowerCase();
      final turma = (a['turma'] ?? '').toString().toLowerCase();
      final onibus = (a['onibus'] ?? '').toString().toLowerCase();
      final quarto = (a['numero_quarto'] ?? '').toString().toLowerCase();

      return nome.contains(query) ||
          cpf.contains(query) ||
          cpfLimpo.contains(query) ||
          turma.contains(query) ||
          onibus.contains(query) ||
          quarto.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoAcesso) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_ehAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cadastro Facial'),
          backgroundColor: const Color(0xFF4C643C),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Acesso restrito a administradores',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'Esta funcionalidade está disponível apenas para usuários com perfil ADMIN.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _exibirSelecaoViagem ? 'Selecionar Viagem' : 'Cadastro Facial',
        ),
        backgroundColor: const Color(0xFF4C643C),
        foregroundColor: Colors.white,
        actions: [
          const SyncStatusIcon(iconSize: 24.0),
          if (_exibirSelecaoViagem)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Recarregar viagens',
              onPressed:
                  _carregandoViagens ? null : _carregarViagensDoServidor,
            )
          else ...[
            IconButton(
              icon: _baixandoAlunos
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.cloud_download),
              tooltip: 'Atualizar alunos da viagem',
              onPressed: (_baixandoAlunos || _viagemSelecionada == null)
                  ? null
                  : () => _baixarAlunosDaViagem(_viagemSelecionada!),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'trocar') {
                  setState(() => _exibirSelecaoViagem = true);
                  await _carregarViagensDoServidor();
                } else if (value == 'limpar') {
                  await _confirmarLimparViagem();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'trocar',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz, size: 20),
                      SizedBox(width: 8),
                      Text('Trocar viagem'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'limpar',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        'Limpar viagem baixada',
                        style: TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          _exibirSelecaoViagem
              ? _buildSelecaoViagemBody()
              : _buildListaAlunosBody(),
          if (_baixandoAlunos)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  margin: EdgeInsets.all(32),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF4C643C)),
                        SizedBox(height: 16),
                        Text(
                          'Baixando alunos da viagem...',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================================
  // VIEW 1: SELEÇÃO DE VIAGEM PARA DOWNLOAD
  // =========================================================================

  Widget _buildSelecaoViagemBody() {
    final viagensFiltradas = _viagensFiltradas;

    return Column(
      children: [
        // Cabeçalho informativo + botão para voltar à viagem já baixada
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4C643C), Color(0xFF3A4F2A)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escolha uma viagem para baixar os alunos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Após baixar, você pode cadastrar as faciais mesmo sem internet.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (_viagemSelecionada != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _exibirSelecaoViagem = false);
                    },
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: Text(
                      'Voltar para ${_viagemSelecionada!['colegio']} (${_alunosViagem.length} alunos)',
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Busca + filtros
        Container(
          color: Colors.grey.shade100,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              TextField(
                controller: _buscaViagemController,
                decoration: InputDecoration(
                  hintText: 'Buscar por colégio, data ou passeio...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscaViagemController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _buscaViagemController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Mostrar encerradas'),
                      selected: _mostrarEncerradas,
                      onSelected: (v) => setState(() => _mostrarEncerradas = v),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Apenas com pernoite'),
                      selected: _apenasPernoite,
                      onSelected: (v) => setState(() => _apenasPernoite = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Lista de viagens
        Expanded(
          child: _carregandoViagens
              ? const Center(child: CircularProgressIndicator())
              : _erroViagens != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.wifi_off,
                              size: 56,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _erroViagens!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _carregarViagensDoServidor,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tentar novamente'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4C643C),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : viagensFiltradas.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.luggage_outlined,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Nenhuma viagem encontrada',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                if (!_mostrarEncerradas && _viagens.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: TextButton(
                                      onPressed: () => setState(
                                        () => _mostrarEncerradas = true,
                                      ),
                                      child: const Text(
                                        'Mostrar viagens encerradas',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _carregarViagensDoServidor,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: viagensFiltradas.length,
                            itemBuilder: (context, index) =>
                                _buildViagemCard(viagensFiltradas[index]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildViagemCard(Map<String, dynamic> viagem) {
    final colegio = (viagem['colegio'] ?? 'Sem Colégio').toString();
    final inicio = (viagem['inicio'] ?? '').toString();
    final fim = (viagem['fim'] ?? '').toString();
    final situacao = (viagem['situacao'] ?? '').toString().toLowerCase();
    final qtdAlunos = (viagem['qtd_alunos'] as num?)?.toInt() ?? 0;
    final faciaisCadastradas =
        (viagem['faciais_cadastradas'] as num?)?.toInt() ?? 0;
    final faciaisPendentes =
        (viagem['faciais_pendentes'] as num?)?.toInt() ??
            (qtdAlunos - faciaisCadastradas).clamp(0, qtdAlunos);
    final pernoite = viagem['pernoite'] == true;
    final onibusList = viagem['onibus'] is List
        ? (viagem['onibus'] as List).map((e) => e.toString()).toList()
        : <String>[];

    final progresso = qtdAlunos > 0 ? faciaisCadastradas / qtdAlunos : 0.0;
    final chave = (viagem['chave'] ?? '$colegio|$inicio').toString();
    final jaBaixada = _viagemSelecionada != null &&
        _viagemSelecionada!['chave'] == chave;

    Color corSituacao;
    String labelSituacao;
    switch (situacao) {
      case 'andamento':
        corSituacao = Colors.green;
        labelSituacao = 'Em andamento';
        break;
      case 'futura':
        corSituacao = Colors.blue;
        labelSituacao = 'Futura';
        break;
      case 'encerrada':
        corSituacao = Colors.grey;
        labelSituacao = 'Encerrada';
        break;
      default:
        corSituacao = Colors.blueGrey;
        labelSituacao = 'Sem data';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: jaBaixada
            ? const BorderSide(color: Color(0xFF4C643C), width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    colegio,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildTag(labelSituacao, corSituacao),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today,
                        size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      _formatarPeriodo(inicio, fim),
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ],
                ),
                if (pernoite) _buildTag('Pernoite', Colors.indigo),
                if (jaBaixada) _buildTag('Baixada', const Color(0xFF4C643C)),
              ],
            ),
            if (onibusList.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Ônibus: ${onibusList.join(', ')}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$faciaisCadastradas de $qtdAlunos faciais',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  faciaisPendentes > 0
                      ? '$faciaisPendentes pendente(s)'
                      : '100% concluído',
                  style: TextStyle(
                    fontSize: 12,
                    color: faciaisPendentes > 0
                        ? Colors.orange.shade800
                        : Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progresso,
                minHeight: 7,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  faciaisPendentes == 0 && qtdAlunos > 0
                      ? Colors.green
                      : const Color(0xFF4C643C),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    _baixandoAlunos ? null : () => _baixarAlunosDaViagem(viagem),
                icon: Icon(
                  jaBaixada ? Icons.sync : Icons.cloud_download,
                  size: 18,
                ),
                label: Text(
                  jaBaixada
                      ? 'ATUALIZAR ALUNOS DA VIAGEM'
                      : 'BAIXAR ALUNOS DA VIAGEM',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4C643C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // =========================================================================
  // VIEW 2: LISTA DE ALUNOS DA VIAGEM BAIXADA + CADASTRO FACIAL
  // =========================================================================

  Widget _buildListaAlunosBody() {
    final total = _alunosViagem.length;
    final cadastrados =
        _alunosViagem.where((a) => a['facial_cadastrada'] == true).length;
    final pendentes = total - cadastrados;
    final porcentagem =
        total > 0 ? ((cadastrados / total) * 100).round() : 0;

    final filtrados = _alunosFiltrados;
    final onibusList = _onibusDisponiveis;

    return Column(
      children: [
        // Cabeçalho da viagem baixada
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4C643C), Color(0xFF3A4F2A)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (_viagemSelecionada?['colegio'] ?? 'Viagem')
                              .toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatarPeriodo(
                            _viagemSelecionada?['inicio']?.toString(),
                            _viagemSelecionada?['fim']?.toString(),
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      setState(() => _exibirSelecaoViagem = true);
                      await _carregarViagensDoServidor();
                    },
                    icon: const Icon(Icons.swap_horiz,
                        color: Colors.white, size: 18),
                    label: const Text(
                      'Trocar',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Total',
                      total.toString(),
                      Icons.people,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'Cadastradas',
                      cadastrados.toString(),
                      Icons.verified_user,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'Pendentes',
                      pendentes.toString(),
                      Icons.face_retouching_off,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: total > 0 ? cadastrados / total : 0.0,
                        minHeight: 7,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.lightGreenAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$porcentagem%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (_viagemSelecionada?['baixado_em'] != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Baixado em ${_formatarHoraIso(_viagemSelecionada!['baixado_em']?.toString())} • Disponível offline',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ],
          ),
        ),

        // Barra de busca e filtros
        Container(
          color: Colors.grey.shade100,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            children: [
              TextField(
                controller: _buscaAlunoController,
                decoration: InputDecoration(
                  hintText: 'Buscar por nome, CPF, turma ou ônibus...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscaAlunoController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _buscaAlunoController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('Todos ($total)'),
                      selected: _filtroFacial == _FiltroFacial.todos,
                      onSelected: (_) =>
                          setState(() => _filtroFacial = _FiltroFacial.todos),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Pendentes ($pendentes)'),
                      selected: _filtroFacial == _FiltroFacial.pendentes,
                      onSelected: (_) => setState(
                        () => _filtroFacial = _FiltroFacial.pendentes,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Cadastrados ($cadastrados)'),
                      selected: _filtroFacial == _FiltroFacial.cadastrados,
                      onSelected: (_) => setState(
                        () => _filtroFacial = _FiltroFacial.cadastrados,
                      ),
                    ),
                    if (onibusList.length > 1) ...[
                      const SizedBox(width: 12),
                      DropdownButtonHideUnderline(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: DropdownButton<String?>(
                            value: _onibusSelecionado,
                            isDense: true,
                            hint: const Text(
                              'Todos ônibus',
                              style: TextStyle(fontSize: 13),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  'Todos ônibus',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                              ...onibusList.map(
                                (bus) => DropdownMenuItem<String?>(
                                  value: bus,
                                  child: Text(
                                    'Ônibus $bus',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (val) =>
                                setState(() => _onibusSelecionado = val),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // Lista de alunos
        Expanded(
          child: filtrados.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _filtroFacial == _FiltroFacial.pendentes &&
                                  pendentes == 0
                              ? Icons.check_circle_outline
                              : Icons.people_outline,
                          size: 64,
                          color: _filtroFacial == _FiltroFacial.pendentes &&
                                  pendentes == 0
                              ? Colors.green
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _filtroFacial == _FiltroFacial.pendentes &&
                                  pendentes == 0
                              ? 'Todas as faciais desta viagem já foram cadastradas!'
                              : 'Nenhum aluno encontrado com os filtros atuais.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: filtrados.length,
                  itemBuilder: (context, index) =>
                      _buildAlunoCard(filtrados[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAlunoCard(Map<String, dynamic> aluno) {
    final nome = (aluno['nome'] ?? 'Sem nome').toString();
    final cpf = (aluno['cpf'] ?? '').toString();
    final turma = (aluno['turma'] ?? '').toString();
    final onibus = (aluno['onibus'] ?? '').toString();
    final quarto = (aluno['numero_quarto'] ?? '').toString();
    final temFacial = aluno['facial_cadastrada'] == true;
    final naFila = _cpfsNaFilaUpload.contains(_limparCpf(cpf));

    final detalhes = <String>[
      if (cpf.isNotEmpty) 'CPF: $cpf',
      if (turma.isNotEmpty) 'Turma: $turma',
      if (onibus.isNotEmpty) 'Ônibus: $onibus',
      if (quarto.isNotEmpty) 'Quarto: $quarto',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  temFacial ? Colors.green.shade100 : Colors.orange.shade100,
              child: Icon(
                temFacial ? Icons.verified_user : Icons.face_retouching_off,
                color:
                    temFacial ? Colors.green.shade700 : Colors.orange.shade800,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nome,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (detalhes.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      detalhes.join(' • '),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _buildTag(
                        temFacial ? 'Facial cadastrada' : 'Pendente',
                        temFacial ? Colors.green.shade700 : Colors.orange.shade800,
                      ),
                      if (naFila) _buildTag('Aguardando envio', Colors.blue),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed:
                  _processandoFacial ? null : () => _cadastrarFacial(aluno),
              icon: const Icon(Icons.camera_alt, size: 18),
              label: Text(temFacial ? 'Refazer' : 'Cadastrar'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    temFacial ? Colors.orange.shade700 : const Color(0xFF4C643C),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
