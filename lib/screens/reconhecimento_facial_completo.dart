// lib/screens/reconhecimento_facial_completo.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/offline_sync_service.dart';
import 'package:embarqueellus/services/alunos_sync_service.dart';

class ReconhecimentoFacialScreen extends StatefulWidget {
  const ReconhecimentoFacialScreen({super.key});

  @override
  State<ReconhecimentoFacialScreen> createState() => _ReconhecimentoFacialScreenState();
}

class _ReconhecimentoFacialScreenState extends State<ReconhecimentoFacialScreen> {
  final _db = DatabaseHelper.instance;
  final _faceService = FaceRecognitionService.instance;

  List<Map<String, dynamic>> _todosAlunos = [];
  List<Map<String, dynamic>> _logsHoje = [];
  bool _carregando = true;
  bool _processando = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarDados();
    FaceRecognitionService.instance.init();

  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    setState(() => _carregando = true);
    try {
      // Sincronizar pessoas com embeddings do Google Sheets
      print('🔄 [Reconhecimento] Sincronizando pessoas com facial...');
      final syncResult = await AlunosSyncService.instance.syncPessoasFromSheets();
      if (syncResult.success) {
        print('✅ [Reconhecimento] ${syncResult.message}');
      } else {
        print('⚠️ [Reconhecimento] Erro ao sincronizar: ${syncResult.message}');
      }

      final alunos = await _db.getAllAlunos();
      final logs = await _db.getLogsHoje();

      setState(() {
        _todosAlunos = alunos;
        _logsHoje = logs;
        _carregando = false;
      });
    } catch (e) {
      print("❌ Erro ao carregar dados: $e");
      setState(() => _carregando = false);
    }
  }

  Future<void> _iniciarReconhecimento() async {
    try {
      final imagePath = await _abrirCameraTela(frontal: false);
      if (imagePath == null) return;

      setState(() => _processando = true);
      _mostrarProgresso('Reconhecendo rosto...');

      final processedImage = await _processarImagemParaModelo(File(imagePath));

      _atualizarProgresso('Comparando com banco de dados...');
      final resultado = await _faceService.recognize(processedImage);

      if (Navigator.canPop(context)) Navigator.pop(context);
      setState(() => _processando = false);

      if (resultado != null) {
        await _selecionarTipoAcesso(resultado);
      } else {
        _mostrarDialogNaoReconhecido();
      }
    } catch (e) {
      print('❌ Erro ao reconhecer aluno: $e');
      if (Navigator.canPop(context)) Navigator.pop(context);
      setState(() => _processando = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Erro: $e')),
      );
    }
  }

  Future<void> _abrirBuscaManual() async {
    final aluno = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _BuscaManualDialog(alunos: _todosAlunos),
    );

    if (aluno != null) {
      await _selecionarTipoAcesso(aluno);
    }
  }

  Future<void> _selecionarTipoAcesso(Map<String, dynamic> aluno) async {
    final tipo = await showDialog<String>(
      context: context,
      builder: (context) => _SelecionarTipoAcessoDialog(aluno: aluno),
    );

    if (tipo != null) {
      await _registrarPassagem(aluno, tipo);
    }
  }

  Future<void> _registrarPassagem(Map<String, dynamic> aluno, String tipo) async {
    try {
      _mostrarProgresso('Registrando passagem...');

      final timestamp = DateTime.now();

      // ✅ Usar score real de similaridade do reconhecimento facial
      // Se não houver score (busca manual), usa 0.95 como fallback
      final confidence = (aluno['similarity_score'] as double?) ?? 0.95;

      // ❌ REMOVIDO: insertLog() duplicado - queueLogAcesso já faz isso
      // await _db.insertLog(...)

      // ✅ ÚNICA ORIGEM DE ESCRITA: queueLogAcesso insere no DB + enfileira para sync
      await OfflineSyncService.instance.queueLogAcesso(
        cpf: aluno['cpf'],
        personName: aluno['nome'],
        timestamp: timestamp,
        confidence: confidence,
        personId: aluno['cpf'],
        tipo: tipo,
      );

      if (Navigator.canPop(context)) Navigator.pop(context);

      await _carregarDados();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${aluno['nome']} registrado: ${_getTipoLabel(tipo)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao registrar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<img.Image> _processarImagemParaModelo(File imageFile) async {
    final bytes = await imageFile.readAsBytes();

    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (e) {
      throw Exception('Falha ao decodificar imagem: $e');
    }

    if (decoded == null) {
      throw Exception('Imagem inválida ou não suportada.');
    }

    if (decoded.numChannels == 1) {
      final rgb = img.Image(
        width: decoded.width,
        height: decoded.height,
        numChannels: 3,
      );
      for (int y = 0; y < decoded.height; y++) {
        for (int x = 0; x < decoded.width; x++) {
          final p = decoded.getPixel(x, y);
          final gray = p.luminance;
          rgb.setPixelRgb(x, y, gray, gray, gray);
        }
      }
      decoded = rgb;
    } else if (decoded.numChannels == 4) {
      final rgb = img.Image(
        width: decoded.width,
        height: decoded.height,
        numChannels: 3,
      );
      for (int y = 0; y < decoded.height; y++) {
        for (int x = 0; x < decoded.width; x++) {
          final p = decoded.getPixel(x, y);
          rgb.setPixelRgb(x, y, p.r, p.g, p.b);
        }
      }
      decoded = rgb;
    }

    final resized = img.copyResize(decoded, width: 160, height: 160);

    if (resized.numChannels != 3) {
      throw Exception(
          'Imagem final não possui 3 canais RGB (${resized.numChannels}).');
    }

    return resized;
  }

  Future<String?> _abrirCameraTela({bool frontal = false}) async {
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
            (c) => frontal
            ? c.lensDirection == CameraLensDirection.front
            : c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final imagePath = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => CameraPreviewScreen(camera: camera),
        ),
      );

      return imagePath;
    } catch (e) {
      print('❌ Erro ao abrir câmera: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao abrir câmera: $e')),
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final alunosComFacial = _todosAlunos.where((a) => a['facial'] != null).length;
    final totalPassagensHoje = _logsHoje.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reconhecimento Facial'),
        backgroundColor: const Color(0xFF4C643C),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarDados,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildHeader(alunosComFacial, totalPassagensHoje),
          _buildBotoesPrincipais(),
          const Divider(height: 1),
          Expanded(child: _buildHistorico()),
        ],
      ),
    );
  }

  Widget _buildHeader(int comFacial, int passagensHoje) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4C643C), Color(0xFF3A4F2A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.face_retouching_natural, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Sistema de Reconhecimento',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatCard('Alunos com Facial', comFacial.toString(), Icons.verified_user),
              _buildStatCard('Passagens Hoje', passagensHoje.toString(), Icons.access_time),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBotoesPrincipais() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _processando ? null : _iniciarReconhecimento,
              icon: const Icon(Icons.camera_alt, size: 28),
              label: const Text(
                'RECONHECER\nPOR FOTO',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4C643C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _processando ? null : _abrirBuscaManual,
              icon: const Icon(Icons.search, size: 28),
              label: const Text(
                'BUSCAR\nPOR NOME',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorico() {
    if (_logsHoje.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Nenhuma passagem registrada hoje',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _logsHoje.length,
      itemBuilder: (context, index) {
        final log = _logsHoje[index];
        return _buildLogCard(log);
      },
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final tipo = log['tipo'] ?? 'desconhecido';
    final nome = log['person_name'] ?? 'Sem nome';
    final timestamp = DateTime.parse(log['timestamp'] ?? DateTime.now().toIso8601String());
    final hora = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

    final tipoInfo = _getTipoInfo(tipo);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tipoInfo['color'].withOpacity(0.2),
          child: Icon(tipoInfo['icon'], color: tipoInfo['color']),
        ),
        title: Text(
          nome,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(tipoInfo['label']),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            hora,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  String _getTipoLabel(String tipo) {
    return _getTipoInfo(tipo)['label'];
  }

  Map<String, dynamic> _getTipoInfo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'quarto':
        return {
          'label': 'Voltou ao Quarto',
          'icon': Icons.bed,
          'color': Colors.blue,
        };
      case 'balada':
        return {
          'label': 'Foi para Balada',
          'icon': Icons.nightlife,
          'color': Colors.purple,
        };
      case 'restaurante':
        return {
          'label': 'Foi ao Restaurante',
          'icon': Icons.restaurant,
          'color': Colors.orange,
        };
      case 'piscina':
        return {
          'label': 'Foi para Piscina',
          'icon': Icons.pool,
          'color': Colors.cyan,
        };
      case 'praia':
        return {
          'label': 'Foi para Praia',
          'icon': Icons.beach_access,
          'color': Colors.amber,
        };
      case 'embarque':
        return {
          'label': 'Embarque Registrado',
          'icon': Icons.login,
          'color': Colors.green,
        };
      default:
        return {
          'label': 'Outro Local',
          'icon': Icons.place,
          'color': Colors.grey,
        };
    }
  }

  void _mostrarProgresso(String mensagem) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  void _atualizarProgresso(String mensagem) {
    if (Navigator.canPop(context)) Navigator.pop(context);
    _mostrarProgresso(mensagem);
  }

  void _mostrarDialogNaoReconhecido() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 12),
            const Text('Não Reconhecido'),
          ],
        ),
        content: const Text(
          'Aluno não encontrado no banco de dados.\n\n'
              'Você pode:\n'
              '• Tentar novamente com melhor iluminação\n'
              '• Buscar manualmente pelo nome',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _abrirBuscaManual();
            },
            child: const Text(
              'Buscar por Nome',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _iniciarReconhecimento();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4C643C),
            ),
            child: const Text('Tentar Novamente'),
          ),
        ],
      ),
    );
  }
}

class _BuscaManualDialog extends StatefulWidget {
  final List<Map<String, dynamic>> alunos;

  const _BuscaManualDialog({required this.alunos});

  @override
  State<_BuscaManualDialog> createState() => _BuscaManualDialogState();
}

class _BuscaManualDialogState extends State<_BuscaManualDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _alunosFiltrados = [];

  @override
  void initState() {
    super.initState();
    _alunosFiltrados = widget.alunos;
    _searchController.addListener(_filtrar);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filtrar() {
    final termo = _searchController.text.toLowerCase();
    setState(() {
      _alunosFiltrados = widget.alunos.where((aluno) {
        final nome = (aluno['nome'] ?? '').toLowerCase();
        final cpf = (aluno['cpf'] ?? '').toLowerCase();
        return nome.contains(termo) || cpf.contains(termo);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.search, color: Color(0xFF4C643C), size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Buscar Aluno',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nome ou CPF',
                prefixIcon: const Icon(Icons.person_search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: _alunosFiltrados.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhum aluno encontrado',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: _alunosFiltrados.length,
                itemBuilder: (context, index) {
                  final aluno = _alunosFiltrados[index];
                  final temFacial = aluno['facial'] != null;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: temFacial
                            ? Colors.green.shade100
                            : Colors.orange.shade100,
                        child: Icon(
                          temFacial ? Icons.face : Icons.face_retouching_off,
                          color: temFacial
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                      title: Text(
                        aluno['nome'] ?? 'Sem nome',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('CPF: ${aluno['cpf'] ?? '--'}'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => Navigator.pop(context, aluno),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelecionarTipoAcessoDialog extends StatelessWidget {
  final Map<String, dynamic> aluno;

  const _SelecionarTipoAcessoDialog({required this.aluno});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.green.shade100,
              child: Icon(
                Icons.check_circle,
                size: 48,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              aluno['nome'] ?? 'Aluno',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'CPF: ${aluno['cpf'] ?? '--'}',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Para onde o aluno está indo?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),

            _buildTipoTile(
              context,
              'Voltou ao Quarto',
              Icons.bed,
              Colors.blue,
              'quarto',
            ),
            _buildTipoTile(
              context,
              'Foi para Balada',
              Icons.nightlife,
              Colors.purple,
              'balada',
            ),
            _buildTipoTile(
              context,
              'Foi ao Restaurante',
              Icons.restaurant,
              Colors.orange,
              'restaurante',
            ),
            _buildTipoTile(
              context,
              'Foi para Piscina',
              Icons.pool,
              Colors.cyan,
              'piscina',
            ),
            _buildTipoTile(
              context,
              'Foi para Praia',
              Icons.beach_access,
              Colors.amber,
              'praia',
            ),

            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipoTile(
      BuildContext context,
      String label,
      IconData icon,
      Color color,
      String tipo,
      ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.pop(context, tipo),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: color.withOpacity(0.9),
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CameraPreviewScreen extends StatefulWidget {
  final CameraDescription camera;
  const CameraPreviewScreen({required this.camera});

  @override
  State<CameraPreviewScreen> createState() => _CameraPreviewScreenState();
}

class _CameraPreviewScreenState extends State<CameraPreviewScreen> {
  CameraController? controller;
  bool _tirandoFoto = false;
  bool _disposed = false;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadCamerasAndInitialize();
  }

  Future<void> _loadCamerasAndInitialize() async {
    try {
      _cameras = await availableCameras();

      // Encontrar o índice da câmera passada
      _currentCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == widget.camera.lensDirection,
      );
      if (_currentCameraIndex == -1) _currentCameraIndex = 0;

      await _initializeCamera();
    } catch (e) {
      print('❌ Erro ao carregar câmeras: $e');
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      if (_cameras.isEmpty) return;

      controller = CameraController(
        _cameras[_currentCameraIndex],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller!.initialize();

      if (mounted && !_disposed) {
        setState(() {});
      }
    } catch (e) {
      print('❌ Erro ao inicializar câmera: $e');
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _trocarCamera() async {
    if (_cameras.length < 2) return;

    setState(() => _tirandoFoto = true);

    try {
      await controller?.dispose();

      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;

      await _initializeCamera();

      setState(() => _tirandoFoto = false);
    } catch (e) {
      print('❌ Erro ao trocar câmera: $e');
      setState(() => _tirandoFoto = false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    controller?.dispose();
    super.dispose();
  }

  Future<void> _tirarFoto() async {
    if (_tirandoFoto || controller == null || !controller!.value.isInitialized) return;

    setState(() => _tirandoFoto = true);

    try {
      final image = await controller!.takePicture();

      if (mounted && !_disposed) {
        Navigator.pop(context, image.path);
      }
    } catch (e) {
      print('❌ Erro ao tirar foto: $e');
      if (mounted && !_disposed) {
        setState(() => _tirandoFoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao capturar foto: $e')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Capturar Rosto'),
          backgroundColor: Color(0xFF4C643C),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                'Inicializando câmera...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capturar Rosto'),
        backgroundColor: const Color(0xFF4C643C),
        actions: [
          if (_cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              onPressed: _tirandoFoto ? null : _trocarCamera,
              tooltip: 'Trocar Câmera',
            ),
        ],
      ),
      body: Stack(
        children: [
          CameraPreview(controller!),

          Center(
            child: Container(
              width: 280,
              height: 350,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(180),
                border: Border.all(
                  color: Colors.greenAccent,
                  width: 3,
                ),
              ),
            ),
          ),

          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Card(
                color: Colors.black54,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Posicione o rosto dentro da moldura',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_cameras.length > 1)
                        const SizedBox(height: 4),
                      if (_cameras.length > 1)
                        Text(
                          _cameras[_currentCameraIndex].lensDirection == CameraLensDirection.front
                              ? '📷 Câmera Frontal'
                              : '📷 Câmera Traseira',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (_tirandoFoto)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      'Processando imagem...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _tirandoFoto ? Colors.grey : const Color(0xFF4C643C),
        onPressed: _tirandoFoto ? null : _tirarFoto,
        child: _tirandoFoto
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.camera_alt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}