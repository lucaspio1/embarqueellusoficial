// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:embarqueellus/screens/main_menu_screen.dart';
import 'package:embarqueellus/screens/login_screen.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/offline_sync_service.dart';
import 'package:embarqueellus/services/auth_service.dart';

const String apiUrl = "https://script.google.com/macros/s/AKfycby14ubSOGVMr7Wzoof-r_pnNKUESSMvhk20z7NO2ZBqvS-DdiErwprhaEQ8Ay99IkIa/exec";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    print('🚀 ========================================');
    print('🚀 ELLUS - Inicializando Aplicação');
    print('🚀 ========================================');

    print('');
    print('💾 [1/4] Inicializando Banco de Dados...');
    final db = DatabaseHelper.instance;
    await db.database;
    await db.ensureFacialSchema();
    print('✅ Banco de dados pronto!');
    print('   - Tabelas: passageiros, alunos, embeddings, logs, sync_queue');

    print('');
    print('🧠 [2/4] Carregando Modelo ArcFace...');
    try {
      await FaceRecognitionService.instance.init();
      print('✅ Modelo ArcFace carregado!');
      print('   - Pronto para reconhecimento offline');
      print('   - Limiar de similaridade: ${(FaceRecognitionService.SIMILARITY_THRESHOLD * 100).toStringAsFixed(0)}%');
    } catch (e) {
      print('⚠️  Aviso: Modelo ArcFace não encontrado');
      print('   Certifique-se que o arquivo existe em:');
      print('   assets/models/arcface.tflite');
      print('   O app funcionará, mas reconhecimento estará desabilitado.');
    }

    print('');
    print('🔄 [3/4] Inicializando Sincronização Offline...');
    OfflineSyncService.instance.init();
    print('✅ Sincronização ativa!');
    print('   - Detecta conectividade automaticamente');
    print('   - Fila de sincronização funcionando');

    print('');
    print('📱 [4/4] Iniciando interface...');
    runApp(const MyApp());
    print('✅ Aplicação iniciada com sucesso!');
    print('🚀 ========================================');
    print('');

    Future.delayed(Duration(seconds: 2), () async {
      try {
        print('🔄 Tentando sincronização inicial em background...');
        OfflineSyncService.instance.trySyncInBackground();
        print('✅ Sincronização inicial iniciada em background');
      } catch (e) {
        print('❌ Erro na sincronização inicial: $e');
      }
    });
  } catch (e) {
    print('❌ ERRO CRÍTICO: $e');
    runApp(ErrorApp(error: e.toString()));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ELLUS - Embarque',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4C643C),
          primary: const Color(0xFF4C643C),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF4C643C),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4C643C),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),

      ),
      home: const AuthCheck(),
    );
  }
}

class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});

  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final isLoggedIn = await AuthService.instance.isLoggedIn();

    if (mounted) {
      if (isLoggedIn) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainMenuScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFD1D2D1),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Color(0xFF4C643C),
            ),
            SizedBox(height: 24),
            Text(
              'Carregando...',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF4C643C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String error;

  const ErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red.shade50,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade700),
                const SizedBox(height: 24),
                const Text(
                  'Erro ao inicializar aplicação',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  error,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}