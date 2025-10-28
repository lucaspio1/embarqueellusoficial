import 'package:flutter/material.dart';
import 'package:embarqueellus/screens/main_menu_screen.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/offline_sync_service.dart';

const String apiUrl = "https://script.google.com/macros/s/AKfycbwdflIAiZfz9PnolgTsvzcVgs_IpugIhYs4-u0YT6SekJPUqGEhawIntA7tG51NlrlT/exec";

void main() async {
  // Garantir que o Flutter esteja inicializado
  WidgetsFlutterBinding.ensureInitialized();

  try {
    print('🚀 ========================================');
    print('🚀 ELLUS - Inicializando Aplicação');
    print('🚀 ========================================');

    // =========================================================================
    // 1. BANCO DE DADOS
    // =========================================================================
    print('');
    print('💾 [1/3] Inicializando Banco de Dados...');
    final db = DatabaseHelper.instance;
    await db.database; // Força inicialização do banco

    // CRÍTICO: Criar tabelas de facial se não existirem
    await db.ensureFacialSchema();

    print('✅ Banco de dados pronto!');
    print('   - Tabelas: passageiros, embeddings, logs, outbox');

    // =========================================================================
    // 2. RECONHECIMENTO FACIAL
    // =========================================================================
    print('');
    print('🧠 [2/3] Carregando Modelo ArcFace...');
    try {
      await FaceRecognitionService.instance.init();
      print('✅ Modelo ArcFace carregado!');
      print('   - Pronto para reconhecimento offline');
    } catch (e) {
      print('⚠️  Aviso: Modelo ArcFace não encontrado');
      print('   Certifique-se que o arquivo existe em:');
      print('   assets/models/arcface.tflite');
      print('   O app funcionará, mas reconhecimento estará desabilitado.');
    }

    // =========================================================================
    // 3. SINCRONIZAÇÃO OFFLINE
    // =========================================================================
    print('');
    print('🔄 [3/3] Iniciando Sincronização Offline...');
    await OfflineSyncService.instance.init();
    print('✅ Sincronização ativa!');
    print('   - Detecta conectividade automaticamente');
    print('   - Fila de sincronização funcionando');

    // =========================================================================
    // FINALIZAÇÃO
    // =========================================================================
    print('');
    print('🎉 ========================================');
    print('🎉 Aplicação inicializada com sucesso!');
    print('🎉 ========================================');
    print('');
  } catch (e, stackTrace) {
    print('');
    print('❌ ========================================');
    print('❌ ERRO NA INICIALIZAÇÃO');
    print('❌ ========================================');
    print('Erro: $e');
    print('');
    print('Stack Trace:');
    print(stackTrace);
    print('');
    print('O app será iniciado, mas algumas funcionalidades');
    print('podem não estar disponíveis.');
    print('========================================');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ellus - Controle de Embarque',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4C643C),
        ),
        useMaterial3: true,

        // Personalizar tema para manter consistência visual
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4C643C),
            foregroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF4C643C),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),

        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),

        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF4C643C),
          foregroundColor: Colors.white,
        ),
      ),
      home: const MainMenuScreen(),
    );
  }
}