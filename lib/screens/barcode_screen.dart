import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Tela unificada para leitura ou digitação de pulseira
class BarcodeScreen extends StatefulWidget {
  const BarcodeScreen({super.key});

  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  final TextEditingController _manualController = TextEditingController();

  bool _isTorchActive = false;
  bool _isProcessing = false;
  bool _modoLeitura = false; // alterna entre digitação e leitura

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Pulseira'),
        backgroundColor: const Color(0xFF4C643C),
        actions: [
          IconButton(
            icon: Icon(
              _modoLeitura ? Icons.keyboard_alt : Icons.qr_code_scanner,
              color: Colors.white,
            ),
            tooltip: _modoLeitura ? 'Usar teclado' : 'Usar câmera',
            onPressed: () {
              setState(() => _modoLeitura = !_modoLeitura);
            },
          ),
          if (_modoLeitura)
            IconButton(
              icon: Icon(
                _isTorchActive ? Icons.flash_on : Icons.flash_off,
                color: _isTorchActive ? Colors.yellow : Colors.white,
              ),
              tooltip: 'Lanterna',
              onPressed: () {
                _cameraController.toggleTorch();
                setState(() => _isTorchActive = !_isTorchActive);
              },
            ),
        ],
      ),
      body: _modoLeitura ? _buildCameraView() : _buildManualView(),
    );
  }

  /// ============================================================
  /// MODO DIGITAÇÃO MANUAL
  /// ============================================================
  Widget _buildManualView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Digite o número da pulseira',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _manualController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Número da Pulseira',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.confirmation_number),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              final codigo = _manualController.text.trim();
              if (codigo.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ Digite um número de pulseira válido.'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.pop(context, codigo);
            },
            icon: const Icon(Icons.check_circle),
            label: const Text('CONFIRMAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4C643C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => setState(() => _modoLeitura = true),
            icon: const Icon(Icons.qr_code),
            label: const Text('Ou escaneie com a câmera'),
          ),
        ],
      ),
    );
  }

  /// ============================================================
  /// MODO LEITURA COM CÂMERA
  /// ============================================================
  Widget _buildCameraView() {
    return Stack(
      children: [
        MobileScanner(
          controller: _cameraController,
          onDetect: (capture) async {
            if (_isProcessing) return;
            _isProcessing = true;

            final barcodes = capture.barcodes;
            if (barcodes.isNotEmpty) {
              final barcode = barcodes.first.rawValue;
              if (barcode != null && barcode.isNotEmpty) {
                Navigator.pop(context, barcode);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ Código inválido.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }

            await Future.delayed(const Duration(milliseconds: 500));
            _isProcessing = false;
          },
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF4C643C), width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const Align(
          alignment: Alignment(0, 0.8),
          child: Text(
            'Aponte para o QR Code da pulseira',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _manualController.dispose();
    super.dispose();
  }
}
