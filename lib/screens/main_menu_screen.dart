import 'package:flutter/material.dart';
import 'package:embarqueellus/screens/controle_embarque_screen.dart';
import 'package:embarqueellus/screens/reconhecimento_facial_completo.dart';
import 'package:embarqueellus/screens/painel_admin_screen.dart';
import 'package:embarqueellus/screens/login_screen.dart';
import 'package:embarqueellus/services/auth_service.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final _authService = AuthService.instance;
  Map<String, dynamic>? _usuario;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarUsuario();
  }

  Future<void> _carregarUsuario() async {
    final usuario = await _authService.getUsuarioLogado();
    setState(() {
      _usuario = usuario;
      _carregando = false;
    });
  }

  Future<void> _realizarLogout() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair'),
        content: const Text('Deseja realmente sair do sistema?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _authService.logout();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
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
                      // Botão de logout no canto superior direito
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          onPressed: _realizarLogout,
                          icon: const Icon(Icons.logout, color: Colors.white),
                          tooltip: 'Sair',
                        ),
                      ),
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
                      if (_usuario != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person, color: Colors.white70, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                _usuario!['nome'] ?? 'Usuário',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              if (_usuario!['perfil']?.toString().toUpperCase() == 'ADMIN') ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'ADMIN',
                                    style: TextStyle(
                                      color: Colors.amber,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
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

                      // Botão Painel (apenas para ADMIN)
                      if (_usuario?['perfil']?.toString().toUpperCase() == 'ADMIN') ...[
                        const SizedBox(height: 16),
                        _buildMenuButton(
                          context: context,
                          label: 'PAINEL',
                          subtitle: 'Área Administrativa',
                          icon: Icons.admin_panel_settings,
                          color: Colors.deepPurple,
                          onPressed: () {
                            print('📍 [MainMenu] Navegando para Painel Admin');
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const PainelAdminScreen(),
                              ),
                            );
                          },
                        ),
                      ],

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
    return Center(
      child: SizedBox(
        width: 320,
        height: subtitle != null ? 110 : 95,
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.visible,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.85),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
