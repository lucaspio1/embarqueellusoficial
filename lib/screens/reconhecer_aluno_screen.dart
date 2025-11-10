import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/models/camera_mode.dart';
import 'package:embarqueellus/models/face_camera_options.dart';
import 'package:embarqueellus/models/face_camera_result.dart';
import 'package:embarqueellus/screens/unified_face_camera_screen.dart';

/// Tela de reconhecimento facial para embarque
/// Reconhece o aluno e retorna seus dados
class ReconhecerAlunoScreen extends StatefulWidget {
  const ReconhecerAlunoScreen({super.key});

  @override
  State<ReconhecerAlunoScreen> createState() => _ReconhecerAlunoScreenState();
}

class _ReconhecerAlunoScreenState extends State<ReconhecerAlunoScreen> {
  bool processando = false;
  bool reconhecido = false;
  String status = "Pronto para reconhecer";
  Map<String, dynamic>? alunoReconhecido;

  @override
  void initState() {
    super.initState();
    _inicializarServico();
    // Captura automática após 1 segundo
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && !processando) {
        _reconhecer();
      }
    });
  }

  Future<void> _inicializarServico() async {
    try {
      await FaceRecognitionService.instance.init();
      print('✅ Face Recognition Service inicializado');
    } catch (e, stackTrace) {
      print('❌ Erro ao inicializar: $e');
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro ao inicializar Face Recognition Service na tela de reconhecimento',
        }),
      );
      if (mounted) {
        setState(() {
          status = 'Erro ao inicializar reconhecimento facial';
        });
      }
    }
  }

  Future<void> _reconhecer() async {
    try {
      if (!mounted) return;

      // Abre tela unificada de câmera em modo de reconhecimento
      final result = await Navigator.push<FaceCameraResult>(
        context,
        MaterialPageRoute(
          builder: (_) => UnifiedFaceCameraScreen(
            mode: CameraMode.recognition,
            options: FaceCameraOptions(
              useFrontCamera: false, // Câmera traseira para melhor qualidade
              title: 'Reconhecer Aluno',
              subtitle: 'Posicione o rosto do aluno',
            ),
          ),
        ),
      );

      // Se cancelou ou não reconheceu
      if (result == null || !result.success) {
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }

      // Se reconheceu com sucesso
      if (result.recognizedPerson != null) {
        final resultado = result.recognizedPerson!;
        setState(() {
          processando = false;
          reconhecido = true;
          status = "Aluno reconhecido!";
          alunoReconhecido = resultado;
        });

        await Sentry.captureMessage(
          'Aluno reconhecido com sucesso na tela de reconhecimento',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setTag('screen', 'reconhecer_aluno');
            scope.setTag('resultado', 'sucesso');
            scope.setContexts('aluno', {
              'nome': resultado['nome'],
              'cpf': resultado['cpf'],
            });
          },
        );

        // Aguardar 2 segundos mostrando resultado
        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          Navigator.pop(context, resultado);
        }
      } else {
        setState(() {
          processando = false;
          reconhecido = false;
          status = "Aluno não reconhecido";
        });

        await Sentry.captureMessage(
          'Falha no reconhecimento facial - Usuário verá dialog de não reconhecido',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('screen', 'reconhecer_aluno');
            scope.setTag('resultado', 'nao_reconhecido');
            scope.setContexts('info', {
              'message': 'Nenhum aluno correspondente foi encontrado no banco de dados',
            });
          },
        );

        if (mounted) {
          _mostrarDialogNaoReconhecido();
        }
      }
    } catch (e, stackTrace) {
      print('❌ Erro ao reconhecer: $e');

      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'context': 'Erro crítico no processo de reconhecimento (tela ReconhecerAlunoScreen)',
        }),
      );

      setState(() {
        processando = false;
        reconhecido = false;
        status = "Erro ao processar";
      });

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

  void _mostrarDialogNaoReconhecido() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 12),
            const Text('Não Reconhecido'),
          ],
        ),
        content: const Text(
          'Aluno não encontrado no banco de dados.\n\n'
              'Certifique-se de que:\n'
              '• O aluno foi cadastrado\n'
              '• A facial está ativa\n'
              '• A iluminação está adequada',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _reconhecer();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD1D2D1),
      appBar: AppBar(
        title: const Text(
          'Reconhecimento Facial',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF4C643C),
        elevation: 0,
      ),
      body: Card(
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
              padding: const EdgeInsets.symmetric(
                vertical: 50.0,
                horizontal: 24.0,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: reconhecido
                      ? [
                    Colors.green.shade700,
                    Colors.green.shade800,
                  ]
                      : [
                    const Color(0xFF4C643C),
                    const Color(0xFF3A4F2A),
                  ],
                ),
              ),
              child: Column(
                children: [
                  // Ícone principal
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(50.0),
                    ),
                    child: Icon(
                      reconhecido
                          ? Icons.verified_user
                          : processando
                          ? Icons.face_retouching_natural
                          : Icons.face,
                      color: Colors.white,
                      size: 64,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Título
                  Text(
                    reconhecido ? 'Reconhecido!' : 'Reconhecimento Facial',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Subtítulo
                  Text(
                    reconhecido ? 'Embarque autorizado' : 'Posicione o rosto',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Status
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (processando)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        if (processando) const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            status,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (reconhecido && alunoReconhecido != null) ...[
                      // Dados do aluno reconhecido
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.green.shade200,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 80,
                              color: Colors.green.shade600,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              alunoReconhecido!['nome'],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'CPF: ${alunoReconhecido!['cpf']}',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (processando) ...[
                      // Processando
                      const CircularProgressIndicator(
                        color: Color(0xFF4C643C),
                        strokeWidth: 4,
                      ),
                      const SizedBox(height: 30),
                      Text(
                        'Analisando rosto...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ] else ...[
                      // Aguardando
                      Icon(
                        Icons.face_retouching_natural,
                        size: 100,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 30),

                      const Text(
                        'Pronto para Reconhecer',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF4C643C),
                        ),
                      ),

                      const SizedBox(height: 16),

                      Text(
                        'A câmera será aberta automaticamente.\n'
                            'Posicione o rosto do aluno para reconhecimento.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Botão de reconhecimento manual
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton.icon(
                          onPressed: _reconhecer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4C643C),
                            foregroundColor: Colors.white,
                            elevation: 8,
                            shadowColor:
                            const Color(0xFF4C643C).withOpacity(0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                          ),
                          icon: const Icon(Icons.camera_alt, size: 28),
                          label: const Text(
                            'RECONHECER AGORA',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Info
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(
                            color: Colors.blue.shade200,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.blue.shade700,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'O reconhecimento é feito localmente usando inteligência artificial.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade900,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}