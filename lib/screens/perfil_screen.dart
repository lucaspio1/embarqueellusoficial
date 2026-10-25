import 'package:flutter/material.dart';
import 'package:embarqueellus/services/auth_service.dart';
import 'package:embarqueellus/screens/login_screen.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final _authService = AuthService.instance;
  final _formKey = GlobalKey<FormState>();

  final _senhaAtualController = TextEditingController();
  final _novaSenhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();

  Map<String, dynamic>? _usuario;
  bool _carregandoUsuario = true;
  bool _salvando = false;

  bool _senhaAtualVisivel = false;
  bool _novaSenhaVisivel = false;
  bool _confirmarSenhaVisivel = false;

  @override
  void initState() {
    super.initState();
    _carregarUsuario();
  }

  @override
  void dispose() {
    _senhaAtualController.dispose();
    _novaSenhaController.dispose();
    _confirmarSenhaController.dispose();
    super.dispose();
  }

  Future<void> _carregarUsuario() async {
    final usuario = await _authService.getUsuarioLogado();
    if (!mounted) return;
    setState(() {
      _usuario = usuario;
      _carregandoUsuario = false;
    });
  }

  String _formatarCpf(String? cpf) {
    if (cpf == null || cpf.isEmpty) return '-';
    final digitos = cpf.replaceAll(RegExp(r'\D'), '');
    if (digitos.length == 11) {
      return '${digitos.substring(0, 3)}.${digitos.substring(3, 6)}.${digitos.substring(6, 9)}-${digitos.substring(9)}';
    }
    return cpf;
  }

  Future<void> _alterarSenha() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _salvando = true);

    try {
      final resultado = await _authService.alterarSenha(
        senhaAtual: _senhaAtualController.text.trim(),
        novaSenha: _novaSenhaController.text.trim(),
      );

      if (!mounted) return;

      if (resultado['success'] == true) {
        _senhaAtualController.clear();
        _novaSenhaController.clear();
        _confirmarSenhaController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${resultado['message'] ?? 'Senha alterada com sucesso!'}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${resultado['message'] ?? 'Erro ao alterar senha.'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro inesperado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
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
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregandoUsuario) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final nome = _usuario?['nome']?.toString() ?? 'Usuário';
    final cpf = _formatarCpf(_usuario?['cpf']?.toString());
    final perfil = (_usuario?['perfil']?.toString() ?? 'USER').toUpperCase();
    final isAdmin = perfil == 'ADMIN';

    return Scaffold(
      backgroundColor: const Color(0xFFD1D2D1),
      appBar: AppBar(
        title: const Text(
          'Meu Perfil',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF4C643C),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card com informações do usuário
              Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF4C643C),
                      Color(0xFF3A4F2A),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      nome,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'CPF: $cpf',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isAdmin
                            ? Colors.amber.withOpacity(0.25)
                            : Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isAdmin ? 'ADMINISTRADOR' : 'MONITOR / USUÁRIO',
                        style: TextStyle(
                          color: isAdmin ? Colors.amber : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Card de Alterar Senha
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lock_reset, color: Color(0xFF4C643C), size: 28),
                            SizedBox(width: 10),
                            Text(
                              'Alterar Senha',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4C643C),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Informe sua senha atual e escolha uma nova senha de acesso.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Senha Atual
                        TextFormField(
                          controller: _senhaAtualController,
                          obscureText: !_senhaAtualVisivel,
                          decoration: InputDecoration(
                            labelText: 'Senha Atual',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _senhaAtualVisivel
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _senhaAtualVisivel = !_senhaAtualVisivel;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Digite sua senha atual';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // Nova Senha
                        TextFormField(
                          controller: _novaSenhaController,
                          obscureText: !_novaSenhaVisivel,
                          decoration: InputDecoration(
                            labelText: 'Nova Senha',
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _novaSenhaVisivel
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _novaSenhaVisivel = !_novaSenhaVisivel;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Digite a nova senha';
                            }
                            if (value.trim().length < 4) {
                              return 'A nova senha deve ter pelo menos 4 caracteres';
                            }
                            if (value.trim() == _senhaAtualController.text.trim()) {
                              return 'A nova senha deve ser diferente da atual';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // Confirmar Nova Senha
                        TextFormField(
                          controller: _confirmarSenhaController,
                          obscureText: !_confirmarSenhaVisivel,
                          decoration: InputDecoration(
                            labelText: 'Confirmar Nova Senha',
                            prefixIcon: const Icon(Icons.check_circle_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _confirmarSenhaVisivel
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _confirmarSenhaVisivel = !_confirmarSenhaVisivel;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Confirme a nova senha';
                            }
                            if (value.trim() != _novaSenhaController.text.trim()) {
                              return 'As senhas não coincidem';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 28),

                        ElevatedButton.icon(
                          onPressed: _salvando ? null : _alterarSenha,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4C643C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                          icon: _salvando
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            _salvando ? 'SALVANDO...' : 'SALVAR NOVA SENHA',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Botão de sair da conta
              OutlinedButton.icon(
                onPressed: _realizarLogout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.red.shade300, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.logout),
                label: const Text(
                  'SAIR DA CONTA',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
