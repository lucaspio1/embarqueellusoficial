import 'package:flutter/material.dart';
import 'package:embarqueellus/widgets/barcode_camera_view.dart';

class BarcodeScreen extends StatefulWidget {
  const BarcodeScreen({super.key});

  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen> {
  bool _modoLeitura = false;
  final TextEditingController _manualController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Pulseira'),
        backgroundColor: const Color(0xFF4C643C),
        actions: [
          IconButton(
            icon: Icon(_modoLeitura ? Icons.keyboard_alt : Icons.qr_code_scanner),
            onPressed: () => setState(() => _modoLeitura = !_modoLeitura),
          ),
        ],
      ),
      body: _modoLeitura ? _buildScannerView() : _buildManualView(),
    );
  }

  Widget _buildManualView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Digite o número da pulseira', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
              if (codigo.isNotEmpty) Navigator.pop(context, codigo);
            },
            icon: const Icon(Icons.check_circle),
            label: const Text('CONFIRMAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4C643C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildScannerView() {
    return BarcodeCameraView(
      onScanned: (code) {
        Navigator.pop(context, code);
      },
    );
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }
}
