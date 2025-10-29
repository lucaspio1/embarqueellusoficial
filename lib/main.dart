// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:embarqueellus/screens/main_menu_screen.dart';
import 'package:embarqueellus/database/database_helper.dart';
import 'package:embarqueellus/services/face_recognition_service.dart';
import 'package:embarqueellus/services/offline_sync_service.dart';

const String apiUrl = "https://script.google.com/macros/s/AKfycbwdflIAiZfz9PnolgTsvzcVgs_IpugIhYs4-u0YT6SekJPUqGEhawIntA7tG51NlrlT/exec";

// ✅ TIMER GLOBAL DE SINCRONIZAÇÃO
Timer? _syncTimer;

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
    print('💾 [1/4] Inicializando Banco de Dados...');
    final db = DatabaseHelper.instance;
    await db.database; // Força inicialização do banco

    // CRÍTICO: Criar tabelas de facial se não existirem
    await db.ensureFacialSchema();

    print('✅ Banco de dados pronto!');
    print('   - Tabelas: passageiros, alunos, embeddings, logs, sync_queue');

    // =========================================================================
    // 2. RECONHECIMENTO FACIAL
    // =========================================================================
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

    // =========================================================================
    // 3. SINCRONIZAÇÃO OFFLINE
    // =========================================================================
    print('');
    print('🔄 [3/4] Inicializando Sincronização Offline...');
    await OfflineSyncService.instance.init();
    print('✅ Sincronização ativa!');
    print('   - Detecta conectividade automaticamente');
    print('   - Fila de sincronização funcionando');

    // =========================================================================
    // 4. ✅ TIMER DE SINCRONIZAÇÃO AUTOMÁTICA (A CADA 3 MINUTOS)
    // =========================================================================
    print('');
    print('⏰ [4/4] Iniciando Timer de Sincronização...');
    _iniciarSincronizacaoAutomatica();
    print('✅ Timer configurado!');
    print('   - Sincroniza automaticamente a cada 3 minutos');
    print('   - Sincronização inicial acontecendo agora...');

    // =========================================================================
    // FINALIZAÇÃO
    // =========================================================================
    print('');
    print('🎉 ========================================');
    print('🎉 Aplicação inicializada com sucesso!');
    print('🎉 ========================================');
    print('');

  } catch (e) {
    print('');
    print('❌ ========================================');
    print('❌ ERRO NA INICIALIZAÇÃO');
    print('❌ ========================================');
    print('❌ $e');
    print('');
  }

  runApp(const MyApp());
}

/// ✅ FUNÇÃO DE SINCRONIZAÇÃO AUTOMÁTICA
void _iniciarSincronizacaoAutomatica() {
  // Cancelar timer anterior se existir
  _syncTimer?.cancel();

  // Criar novo timer que executa a cada 3 minutos
  _syncTimer = Timer.periodic(const Duration(minutes: 3), (timer) async {
    print('');
    print('⏰ ========================================');
    print('⏰ Timer de Sincronização Disparado');
    print('⏰ ========================================');

    try {
      // Tentar sincronizar agora
      final sucesso = await OfflineSyncService.instance.trySyncNow();

      if (sucesso) {
        print('✅ Sincronização automática concluída com sucesso!');
      } else {
        print('⚠️ Sincronização não executada (sem internet ou sem dados)');
      }
    } catch (e) {
      print('❌ Erro na sincronização automática: $e');
    }

    print('⏰ Próxima sincronização em 3 minutos...');
    print('⏰ ========================================');
    print('');
  });

  // Executar primeira sincronização imediatamente
  Future.delayed(const Duration(seconds: 2), () async {
    print('');
    print('🔄 ========================================');
    print('🔄 Sincronização Inicial');
    print('🔄 ========================================');

    try {
      final sucesso = await OfflineSyncService.instance.trySyncNow();

      if (sucesso) {
        print('✅ Sincronização inicial concluída!');
      } else {
        print('📵 Sincronização inicial não executada (sem internet ou sem dados pendentes)');
      }
    } catch (e) {
      print('❌ Erro na sincronização inicial: $e');
    }

    print('🔄 ========================================');
    print('');
  });
}

/// ✅ FUNÇÃO PARA PARAR SINCRONIZAÇÃO (caso necessário)
void pararSincronizacao() {
  _syncTimer?.cancel();
  _syncTimer = null;
  print('🛑 Timer de sincronização parado');
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
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const MainMenuScreen(),
    );
  }
}