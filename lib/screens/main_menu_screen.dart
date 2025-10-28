import 'package:flutter/material.dart';
import 'package:embarqueellus/screens/controle_embarque_screen.dart';
import 'package:embarqueellus/screens/controle_alunos_screen.dart';
import 'package:embarqueellus/screens/reconhecimento_facial_completo.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD1D2D1),
      body: SafeArea(
        child: SingleChildScrollView( // ✅ Permite rolar o conteúdo
          child: Card(
            elevation: 8,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 50.0, horizontal: 24.0),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF4C643C),
                        Color(0xFF3A4F2A),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(50.0),
                        ),
                        child: const Icon(
                          Icons.school,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Ellus',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Educação e Turismo',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                ),

                // Body
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Sistema de Controle',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF4C643C),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // Botão Controle Embarque
                      _buildMenuButton(
                        context: context,
                        label: 'CONTROLE EMBARQUE',
                        icon: Icons.directions_bus,
                        color: const Color(0xFF4C643C),
                        onPressed: () {
                          print('📍 [MainMenu] Navegando para Controle Embarque');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ControleEmbarqueScreen(),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // Botão Reconhecimento Facial
                      _buildMenuButton(
                        context: context,
                        label: 'RECONHECIMENTO FACIAL',
                        subtitle: 'Registrar Passagens',
                        icon: Icons.face_retouching_natural,
                        color: Colors.indigo,
                        onPressed: () {
                          print('📍 [MainMenu] Navegando para Reconhecimento Facial');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ReconhecimentoFacialScreen(),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // Botão Gerenciar Alunos
                      _buildMenuButton(
                        context: context,
                        label: 'GERENCIAR ALUNOS',
                        subtitle: 'Cadastrar Faciais',
                        icon: Icons.face,
                        color: Colors.teal,
                        onPressed: () {
                          print('📍 [MainMenu] Navegando para Controle Alunos');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ControleAlunosScreen(),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 32),

                      // Footer info
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.grey.shade600,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Dados sincronizados automaticamente com a nuvem',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton({
    required BuildContext context,
    required String label,
    String? subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      height: subtitle != null ? 110 : 90,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 8,
          shadowColor: color.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
