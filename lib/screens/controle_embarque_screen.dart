import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:embarqueellus/screens/embarque_screen.dart';
import 'package:embarqueellus/services/data_service.dart';
import 'package:embarqueellus/screens/retorno_screen.dart';
import 'package:embarqueellus/services/retorno_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/screens/controle_alunos_screen.dart';
import 'package:embarqueellus/screens/main_menu_screen.dart';
import 'package:embarqueellus/widgets/barcode_camera_view.dart';

import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class ControleEmbarqueScreen extends StatefulWidget {
  const ControleEmbarqueScreen({super.key});

  @override
  State<ControleEmbarqueScreen> createState() => _ControleEmbarqueScreenState();
}

class _ControleEmbarqueScreenState extends State<ControleEmbarqueScreen> {
  String? _nomeAba;
  String? _nomePasseio;
  String? _numeroOnibus;
  String? _pulseira;
  int _totalAlunos = 0;
  int _totalEmbarcados = 0;
  int _totalRetornados = 0;
  int _totalFaciaisCadastradas = 0;
  bool _temDadosSalvos = false;
  bool _temAlunosComQR = false;

  @override
  void initState() {
    super.initState();
    _verificarDadosSalvos();
  }

  Future<void> _verificarDadosSalvos() async {
    final prefs = await SharedPreferences.getInstance();
    final nomeAba = prefs.getString('nome_aba');
    final nomePasseio = prefs.getString('nome_passeio');
    final numeroOnibus = prefs.getString('numero_onibus');
    final pulseira = prefs.getString('pulseira');

    if (!mounted) return;

    if (nomeAba != null && numeroOnibus != null) {
      await DataService().loadLocalData(nomeAba, numeroOnibus);
      if (!mounted) return;

      final passageiros = DataService().passageirosEmbarque.value;

      // ✅ CORREÇÃO: Contar apenas faciais DOS PASSAGEIROS DESTA LISTA
      // Não contar todas as faciais do banco (que incluem outras viagens)
      final db = DatabaseHelper.instance;
      final cpfsDosPassageiros = passageiros
          .where((p) => p.cpf != null && p.cpf!.isNotEmpty)
          .map((p) => p.cpf!)
          .toList();
      final totalFaciaisDaLista = await db.contarFaciaisDaListaEmbarque(cpfsDosPassageiros);

      setState(() {
        _nomeAba = nomeAba;
        _nomePasseio = nomePasseio ?? nomeAba;
        _numeroOnibus = numeroOnibus;
        _pulseira = pulseira ?? 'NÃO INFORMADO';
        _totalAlunos = passageiros.length;
        _totalEmbarcados = passageiros.where((p) => p.embarque == 'SIM').length;
        _totalRetornados = passageiros.where((p) => p.retorno == 'SIM').length;
        _totalFaciaisCadastradas = totalFaciaisDaLista;
        // Mostrar botão se pulseira == 'SIM' no QR Code
        _temAlunosComQR = pulseira?.toUpperCase() == 'SIM';
        _temDadosSalvos = true;
      });
    } else {
      if (!mounted) return;
      setState(() => _temDadosSalvos = false);
    }
  }

  Future<void> _escanearQRCode() async {
    if (!mounted) return;
    final resultado = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (context) => const QRCodeScannerScreen()),
    );

    if (!mounted) return;

    if (resultado != null) {
      final nomeAba = resultado['nomeAba']!;
      final nomePasseio = resultado['nomePasseio']!;
      final numeroOnibus = resultado['numeroOnibus']!;
      final pulseira = resultado['pulseira'] ?? 'NÃO';

      if (!mounted) return;
      setState(() => _pulseira = pulseira);

      await _carregarDadosDoServidor(nomeAba, nomePasseio, numeroOnibus);
    }
  }

  Future<void> _carregarDadosDoServidor(
      String nomeAba, String nomePasseio, String numeroOnibus) async {
    bool dialogAberto = false;

    try {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      dialogAberto = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      await prefs.setString('nome_aba', nomeAba);
      await prefs.setString('nome_passeio', nomePasseio);
      await prefs.setString('numero_onibus', numeroOnibus);
      await prefs.setString('pulseira', _pulseira ?? '');

      await DataService().fetchData(nomeAba, onibus: numeroOnibus);
      final totalAlunos = DataService().passageirosEmbarque.value.length;

      if (!mounted) return;
      if (dialogAberto) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogAberto = false;
      }

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      await _verificarDadosSalvos();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✔️ $totalAlunos alunos carregados com sucesso!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (dialogAberto && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _irParaEmbarque() async {
    if (!mounted) return;
    await DataService().loadLocalData(_nomeAba!, _numeroOnibus!);
    if (!mounted) return;
    final totalAlunos = DataService().passageirosEmbarque.value.length;

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmbarqueScreen(
          colegio: _nomeAba!,
          onibus: _numeroOnibus!,
          totalAlunos: totalAlunos,
        ),
      ),
    ).then((_) => _verificarDadosSalvos());
  }

  Future<void> _irParaRetorno() async {
    if (!mounted) return;
    await RetornoService().loadLocalDataFromEmbarque(_nomeAba!, _numeroOnibus!);
    if (!mounted) return;
    final totalAlunos = RetornoService().passageirosRetorno.value.length;

    if (totalAlunos == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Nenhum aluno embarcado ainda'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RetornoScreen(
          colegio: _nomeAba!,
          onibus: _numeroOnibus!,
          totalAlunos: totalAlunos,
        ),
      ),
    ).then((_) => _verificarDadosSalvos());
  }

  void _mostrarConfirmacaoEncerramento() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('⚠️ Encerrar Passeio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Isso irá limpar TODOS os dados locais!',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 16),
              Text('• Total de alunos: $_totalAlunos'),
              Text('• Embarcados: $_totalEmbarcados'),
              Text('• Retornados: $_totalRetornados'),
              const SizedBox(height: 16),
              const Text('Deseja realmente encerrar?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Sim, Encerrar', style: TextStyle(color: Colors.red)),
              onPressed: () => _encerrarPasseio(dialogContext),
            ),
          ],
        );
      },
    );
  }

  Future<void> _encerrarPasseio(BuildContext dialogContext) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;

    DataService().passageirosEmbarque.value = [];
    RetornoService().passageirosRetorno.value = [];

    if (!mounted) return;
    Navigator.of(dialogContext).pop();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainMenuScreen()),
          (route) => false,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✔️ Passeio encerrado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controle de Embarque'),
        backgroundColor: const Color(0xFF4C643C),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Icon(Icons.directions_bus,
                          color: Color(0xFF4C643C), size: 60),
                      const SizedBox(height: 16),
                      if (_temDadosSalvos) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('DADOS CARREGADOS',
                              style: TextStyle(color: Colors.white, fontSize: 10)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _nomePasseio ?? '',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4C643C)),
                        ),
                        const SizedBox(height: 8),
                        Text('Ônibus: $_numeroOnibus',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey.shade700)),
                        if (_pulseira != null && _pulseira!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('FACIAL: $_pulseira',
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600)),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildInfoCard('Total', _totalAlunos, Colors.blue),
                            _buildInfoCard('Embarcados', _totalEmbarcados, Colors.green),
                            _buildInfoCard('Faciais', _totalFaciaisCadastradas, Colors.purple),
                            _buildInfoCard('Retornados', _totalRetornados, Colors.orange),
                          ],
                        ),
                      ] else
                        const Text('Escaneie o QR Code para começar',
                            style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic),
                            textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              if (!_temDadosSalvos)
                ElevatedButton.icon(
                  onPressed: _escanearQRCode,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('ESCANEAR QR CODE'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4C643C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18)),
                )
              else ...[
                ElevatedButton.icon(
                  onPressed: _irParaEmbarque,
                  icon: const Icon(Icons.login),
                  label: const Text('CONTINUAR EMBARQUE'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4C643C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18)),
                ),
                const SizedBox(height: 16),
                // Botão Gerenciar Alunos - Aparece apenas se houver alunos com QR/pulseira
                if (_temAlunosComQR) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ControleAlunosScreen(),
                        ),
                      ).then((_) => _verificarDadosSalvos());
                    },
                    icon: const Icon(Icons.face),
                    label: const Text('GERENCIAR ALUNOS'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18)),
                  ),
                  const SizedBox(height: 16),
                ],
                ElevatedButton.icon(
                  onPressed: _irParaRetorno,
                  icon: const Icon(Icons.logout),
                  label: const Text('IR PARA RETORNO'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18)),
                ),
                const SizedBox(height: 16),

                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _mostrarConfirmacaoEncerramento,
                  icon: const Icon(Icons.stop_circle),
                  label: const Text('ENCERRAR PASSEIO'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String label, int valor, Color cor) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Text(valor.toString(),
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: cor)),
      ],
    );
  }
}

// ============================================================================
// TELA DE SCANNER USANDO GOOGLE MLKIT BARCODE SCANNING
// ============================================================================
class QRCodeScannerScreen extends StatefulWidget {
  const QRCodeScannerScreen({super.key});

  @override
  State<QRCodeScannerScreen> createState() => _QRCodeScannerScreenState();
}

class _QRCodeScannerScreenState extends State<QRCodeScannerScreen> {
  final TextEditingController _manualInputController = TextEditingController();
  bool _showManualInput = false;

  @override
  void dispose() {
    _manualInputController.dispose();
    super.dispose();
  }

  void _processQrData(String value) {
    final partes = value.split(';');
    if (partes.length >= 4) {
      Navigator.pop(context, {
        'nomeAba': partes[0].trim(),
        'nomePasseio': partes[1].trim(),
        'numeroOnibus': partes[2].trim(),
        'pulseira': partes[3].trim(),
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Formato inválido. Use: NomeAba;NomePasseio;NumeroOnibus;Pulseira'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _processManualInput() {
    final value = _manualInputController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Digite os dados no formato: NomeAba;NomePasseio;NumeroOnibus;Pulseira'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    _processQrData(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR Code'),
        backgroundColor: const Color(0xFF4C643C),
        actions: [
          IconButton(
            icon: Icon(_showManualInput ? Icons.qr_code_scanner : Icons.keyboard),
            onPressed: () {
              setState(() {
                _showManualInput = !_showManualInput;
              });
            },
            tooltip: _showManualInput ? 'Voltar para Scanner' : 'Entrada Manual',
          ),
        ],
      ),
      body: _showManualInput ? _buildManualInput() : _buildScanner(),
    );
  }

  Widget _buildScanner() {
    return BarcodeCameraView(
      onScanned: _processQrData,
    );
  }

  Widget _buildManualInput() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.edit_note,
            size: 80,
            color: Color(0xFF4C643C),
          ),
          const SizedBox(height: 24),
          const Text(
            'Entrada Manual',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4C643C),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Digite os dados no formato:',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Text(
              'NomeAba;NomePasseio;NumeroOnibus;Pulseira',
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _manualInputController,
            decoration: InputDecoration(
              labelText: 'Dados do QR Code',
              hintText: 'Ex: Escola ABC;Passeio XYZ;Bus01;SIM',
              prefixIcon: const Icon(Icons.text_fields),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            maxLines: 3,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _processManualInput(),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _processManualInput,
            icon: const Icon(Icons.check_circle, size: 24),
            label: const Text(
              'CONFIRMAR',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4C643C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'Explicação dos campos:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Nome da Aba', 'Nome da planilha/colégio'),
          _buildInfoRow('Nome do Passeio', 'Nome do evento/viagem'),
          _buildInfoRow('Número do Ônibus', 'Identificação do ônibus'),
          _buildInfoRow('Pulseira/Facial', 'SIM ou NÃO (uso de facial)'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: Color(0xFF4C643C)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
