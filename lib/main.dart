// lib/main.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:embarqueellus/screens/main_menu_screen.dart';
import 'package:embarqueellus/screens/login_screen.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/offline_sync_service.dart';
import 'package:embarqueellus/services/auth_service.dart';
import 'package:embarqueellus/config/app_config.dart';

Future<void> main() async {
  // ✅ DIAGNÓSTICO: Verificar modo de build ANTES de inicializar Sentry
  print('');
  print('🔍 ========================================');
  print('🔍 DIAGNÓSTICO DE BUILD iOS');
  print('🔍 ========================================');
  print('📱 kDebugMode: $kDebugMode');
  print('📱 kReleaseMode: $kReleaseMode');
  print('📱 kProfileMode: $kProfileMode');

  if (kDebugMode) {
    print('⚠️  ATENÇÃO: App em modo DEBUG');
    print('⚠️  Sentry NÃO funciona em Debug no iOS!');
    print('⚠️  Use: flutter run --profile ou flutter run --release');
  } else if (kProfileMode) {
    print('✅ App em modo PROFILE - Sentry funcionará');
  } else if (kReleaseMode) {
    print('✅ App em modo RELEASE - Sentry funcionará');
  }
  print('🔍 ========================================');
  print('');

  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://16c773f79c6fc2a3a4951733ce3570ed@o4504103203045376.ingest.us.sentry.io/4510326779740160';
      options.tracesSampleRate = 1.0;
      // ✅ Debug habilitado apenas em modo Debug, desabilitado em Release/Profile
      options.debug = kDebugMode;
      // ✅ Environment correto: production em release, development em debug
      options.environment = kReleaseMode ? 'production' : 'development';

      // ✅ Callback para verificar se Sentry está enviando eventos
      options.beforeSend = (event, hint) {
        print('📤 Sentry: Tentando enviar evento: ${event.message?.formatted ?? event.exception}');
        return event;
      };
    },
    appRunner: () async {
      print('');
      print('🔍 ========================================');
      print('🔍 TESTE DE INICIALIZAÇÃO DO SENTRY');
      print('🔍 ========================================');

      try {
        // ✅ Teste 1: Enviar mensagem de teste
        print('🧪 Teste 1: Enviando mensagem de teste...');
        await Sentry.captureMessage(
          'iOS: App iniciado - Teste de conectividade Sentry (v1.0.7)',
          level: SentryLevel.info,
          withScope: (scope) {
            scope.setTag('platform', 'iOS');
            scope.setTag('test_type', 'initialization');
            scope.setTag('build_mode', kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'));
          },
        );
        print('✅ Mensagem de teste enviada ao Sentry');

        // ✅ Teste 2: Enviar exceção de teste
        print('🧪 Teste 2: Enviando exceção de teste...');
        await Sentry.captureException(
          Exception('iOS: Teste de exceção - Verificando conectividade Sentry'),
          stackTrace: StackTrace.current,
          hint: Hint.withMap({
            'platform': 'iOS',
            'test_type': 'exception_test',
            'build_mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
          }),
        );
        print('✅ Exceção de teste enviada ao Sentry');

        print('✅ Sentry inicializado e eventos de teste enviados');
        print('🔍 ========================================');
        print('');
      } catch (e) {
        print('❌ ERRO ao enviar eventos de teste para Sentry: $e');
        print('🔍 ========================================');
        print('');
      }

      WidgetsFlutterBinding.ensureInitialized();

      // Carregar arquivo .env
      try {
        await dotenv.load(fileName: ".env");
        print('✅ Arquivo .env carregado com sucesso');
      } catch (e) {
        print('⚠️  Erro ao carregar .env: $e');
        print('   Certifique-se que o arquivo .env existe na raiz do projeto');
        await Sentry.captureException(e, hint: Hint.withMap({'context': 'Erro ao carregar .env'}));
      }

      try {
        print('🚀 ========================================');
        print('🚀 ELLUS - Inicializando Aplicação');
        print('🚀 ========================================');

        print('');
        print('⚙️  [1/5] Validando Configurações...');
        AppConfig.instance.printConfig();
        if (!AppConfig.instance.isValid) {
          print('❌ ERRO: Configurações inválidas!');
          print('   Verifique o arquivo .env na raiz do projeto');
          await Sentry.captureMessage(
            'Configurações inválidas no AppConfig',
            level: SentryLevel.error,
          );
        } else {
          print('✅ Configurações válidas!');
        }

        print('');
        print('💾 [2/5] Inicializando Banco de Dados...');
        final db = DatabaseHelper.instance;
        await db.database;
        await db.ensureFacialSchema();
        print('✅ Banco de dados pronto!');
        print('   - Tabelas: passageiros, alunos, embeddings, logs, sync_queue');

        print('');
        print('🧠 [3/5] Carregando Modelo ArcFace...');
        try {
          await FaceRecognitionService.instance.init();
          print('✅ Modelo ArcFace carregado!');
          print('   - Pronto para reconhecimento offline');
          print('   - Limiar L2: ${FaceRecognitionService.DISTANCE_THRESHOLD.toStringAsFixed(2)}');
        } catch (e) {
          print('⚠️  Aviso: Modelo ArcFace não encontrado');
          print('   Certifique-se que o arquivo existe em:');
          print('   assets/models/arcface.tflite');
          print('   O app funcionará, mas reconhecimento estará desabilitado.');
          await Sentry.captureException(
            e,
            hint: Hint.withMap({'context': 'Erro ao carregar modelo ArcFace'}),
          );
        }

        print('');
        print('🔄 [4/5] Inicializando Sincronização Offline...');
        OfflineSyncService.instance.init();
        print('✅ Sincronização ativa!');
        print('   - Detecta conectividade automaticamente');
        print('   - Fila de sincronização funcionando');

        print('');
        print('📱 [5/5] Iniciando interface...');
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
            await Sentry.captureException(
              e,
              hint: Hint.withMap({'context': 'Erro na sincronização inicial'}),
            );
          }
        });
      } catch (e, stackTrace) {
        print('❌ ERRO CRÍTICO: $e');
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