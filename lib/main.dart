// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:embarqueellus/screens/main_menu_screen.dart';
import 'package:embarqueellus/screens/login_screen.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/firebase_service.dart';
import 'package:embarqueellus/services/auth_service.dart';
import 'package:embarqueellus/config/app_config.dart';

Future<void> main() async {
  // ✅ CRÍTICO: Capturar TODOS os erros não tratados (Flutter + Dart)
  FlutterError.onError = (FlutterErrorDetails details) async {
    await Sentry.captureException(
      details.exception,
      stackTrace: details.stack,
      hint: Hint.withMap({'context': 'Flutter Framework Error'}),
    );
  };

  // ✅ Capturar erros assíncronos não tratados
  PlatformDispatcher.instance.onError = (error, stack) {
    Sentry.captureException(
      error,
      stackTrace: stack,
      hint: Hint.withMap({'context': 'Async Unhandled Error'}),
    );
    return true;
  };

  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://16c773f79c6fc2a3a4951733ce3570ed@o4504103203045376.ingest.us.sentry.io/4510326779740160';
      options.tracesSampleRate = 1.0;

      // ✅ CRÍTICO: SEMPRE habilitar debug para diagnóstico (remover depois que funcionar)
      options.debug = true;

      // ✅ Environment correto: production em release, development em debug
      options.environment = kReleaseMode ? 'production' : 'development';

      // ✅ Configurações extras para iOS
      options.enableAutoSessionTracking = true;
      // options.attachScreenshot = true;  // Disponível em versões mais recentes
      // options.screenshotQuality = SentryScreenshotQuality.low;
      // options.attachViewHierarchy = true;  // Disponível em versões mais recentes
    },
    appRunner: () async {
      // ✅ TESTE IMEDIATO: Enviar evento de teste
      await Sentry.captureMessage(
        '✅ App Flutter iniciado com sucesso! Platform: ${Platform.isIOS ? "iOS" : "Android"}',
        level: SentryLevel.info,
      );
      WidgetsFlutterBinding.ensureInitialized();

      // Carregar arquivo .env
      try {
        await dotenv.load(fileName: ".env");
      } catch (e) {
        await Sentry.captureException(e, hint: Hint.withMap({'context': 'Erro ao carregar .env'}));
      }

      try {
        // ✅ IMPORTANTE: Inicializar Firebase ANTES de tudo
        print('🔥 Inicializando Firebase...');
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        print('✅ Firebase inicializado com sucesso');

        AppConfig.instance.printConfig();
        if (!AppConfig.instance.isValid) {
          await Sentry.captureMessage(
            'Configurações inválidas no AppConfig',
            level: SentryLevel.error,
          );
        }

        final db = DatabaseHelper.instance;
        await db.database;
        await db.ensureFacialSchema();

        try {
          await FaceRecognitionService.instance.init();
        } catch (e) {
          await Sentry.captureException(
            e,
            hint: Hint.withMap({'context': 'Erro ao carregar modelo ArcFace'}),
          );
        }

        // ✅ Inicializar FirebaseService (substitui OfflineSyncService)
        print('🔥 Inicializando FirebaseService...');
        FirebaseService.instance.init();
        print('✅ FirebaseService inicializado com sucesso');

        runApp(const MyApp());

        Future.delayed(Duration(seconds: 2), () async {
          try {
            // ✅ Usar FirebaseService para sincronização em background
            FirebaseService.instance.trySyncInBackground();
          } catch (e) {
            await Sentry.captureException(
              e,
              hint: Hint.withMap({'context': 'Erro na sincronização inicial'}),
            );
          }
        });
      } catch (e, stackTrace) {
        await Sentry.captureException(
          e,
          stackTrace: stackTrace,
          hint: Hint.withMap({'context': 'Erro crítico na inicialização'}),
        );
        runApp(ErrorApp(error: e.toString()));
      }
    },
  );
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
        // ✅ OTIMIZAÇÃO: Remover animações de página para performance
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: OpenUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
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