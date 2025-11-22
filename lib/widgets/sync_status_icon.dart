// lib/widgets/sync_status_icon.dart
// Widget de feedback visual do estado de sincronização
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:embarqueellus/services/offline_sync_service.dart';
import 'package:embarqueellus/database/database_helper.dart';

/// Estados possíveis da sincronização
enum SyncState {
  /// Estado inicial ou sincronizado com sucesso (sem pendências)
  idle,

  /// Sincronização em andamento
  syncing,

  /// Erro na sincronização ou há itens pendentes
  error,

  /// Sem conexão com internet
  offline,
}

/// Widget que exibe o status de sincronização com ícone e cor apropriados
///
/// Estados visuais:
/// - Verde (Check): Tudo sincronizado, sem pendências
/// - Azul (Spinning): Sincronização em andamento
/// - Amarelo/Laranja: Há itens pendentes aguardando sync
/// - Vermelho: Erro na sincronização ou sem conexão
///
/// Uso:
/// ```dart
/// AppBar(
///   title: Text('Minha Tela'),
///   actions: [
///     SyncStatusIcon(),
///   ],
/// )
/// ```
class SyncStatusIcon extends StatefulWidget {
  /// Intervalo de atualização do status (em segundos)
  final int updateIntervalSeconds;

  /// Se deve exibir tooltip ao passar o mouse
  final bool showTooltip;

  /// Tamanho do ícone
  final double iconSize;

  const SyncStatusIcon({
    Key? key,
    this.updateIntervalSeconds = 5,
    this.showTooltip = true,
    this.iconSize = 24.0,
  }) : super(key: key);

  @override
  State<SyncStatusIcon> createState() => _SyncStatusIconState();
}

class _SyncStatusIconState extends State<SyncStatusIcon> {
  final OfflineSyncService _syncService = OfflineSyncService.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  SyncState _currentState = SyncState.idle;
  Timer? _updateTimer;
  int _pendingCount = 0;
  String _lastSyncTime = 'Nunca';

  @override
  void initState() {
    super.initState();
    _updateStatus();

    // Timer periódico para atualizar o status
    _updateTimer = Timer.periodic(
      Duration(seconds: widget.updateIntervalSeconds),
      (_) => _updateStatus(),
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  /// Atualiza o status de sincronização
  Future<void> _updateStatus() async {
    try {
      // Verificar se há sincronização em andamento
      // (você pode adicionar uma flag no OfflineSyncService para isso)

      // Contar itens pendentes
      final logsPendentes = await _db.contarLogsPendentes();
      final outboxBatch = await _db.getOutboxBatch(limit: 1);
      final totalPendentes = logsPendentes + outboxBatch.length;

      // Determinar novo estado
      SyncState newState;
      if (totalPendentes > 0) {
        newState = SyncState.error; // Há pendências
      } else {
        newState = SyncState.idle; // Tudo sincronizado
      }

      // Atualizar UI se o estado mudou
      if (mounted && (newState != _currentState || totalPendentes != _pendingCount)) {
        setState(() {
          _currentState = newState;
          _pendingCount = totalPendentes;
        });
      }
    } catch (e) {
      print('⚠️ [SyncStatusIcon] Erro ao atualizar status: $e');
      if (mounted) {
        setState(() {
          _currentState = SyncState.offline;
        });
      }
    }
  }

  /// Retorna a cor baseada no estado
  Color _getColor() {
    switch (_currentState) {
      case SyncState.idle:
        return Colors.green; // Verde = Tudo OK
      case SyncState.syncing:
        return Colors.blue; // Azul = Sincronizando
      case SyncState.error:
        return Colors.orange; // Laranja = Pendências
      case SyncState.offline:
        return Colors.red; // Vermelho = Sem conexão
    }
  }

  /// Retorna o ícone baseado no estado
  IconData _getIcon() {
    switch (_currentState) {
      case SyncState.idle:
        return Icons.cloud_done; // Nuvem com check
      case SyncState.syncing:
        return Icons.cloud_sync; // Nuvem sincronizando
      case SyncState.error:
        return Icons.cloud_upload; // Nuvem com upload
      case SyncState.offline:
        return Icons.cloud_off; // Nuvem desconectada
    }
  }

  /// Retorna o texto do tooltip
  String _getTooltip() {
    switch (_currentState) {
      case SyncState.idle:
        return 'Sincronizado ✓\nTodos os dados estão atualizados';
      case SyncState.syncing:
        return 'Sincronizando...\nAguarde enquanto os dados são enviados';
      case SyncState.error:
        return 'Itens pendentes: $_pendingCount\nClique para sincronizar agora';
      case SyncState.offline:
        return 'Sem conexão\nVerifique sua internet';
    }
  }

  /// Callback quando o ícone é clicado
  Future<void> _onTap() async {
    if (_currentState == SyncState.idle) {
      // Se está idle, não faz nada ou mostra mensagem de sucesso
      _showSnackBar('Tudo sincronizado! ✓', Colors.green);
      return;
    }

    // Tentar sincronizar agora
    setState(() {
      _currentState = SyncState.syncing;
    });

    _showSnackBar('Iniciando sincronização...', Colors.blue);

    try {
      // Sincronizar outbox
      await _syncService.trySyncNow();

      // Sincronizar logs pendentes
      final totalSincronizados = await _syncService.sincronizarLogsPendentes();

      // Atualizar status
      await _updateStatus();

      if (_currentState == SyncState.idle) {
        _showSnackBar(
          'Sincronização concluída! ✓\n$totalSincronizados logs enviados',
          Colors.green,
        );
      } else {
        _showSnackBar(
          'Sincronização parcial\nAinda há $_pendingCount itens pendentes',
          Colors.orange,
        );
      }
    } catch (e) {
      print('❌ [SyncStatusIcon] Erro ao sincronizar: $e');
      _showSnackBar('Erro ao sincronizar\nTente novamente', Colors.red);

      setState(() {
        _currentState = SyncState.error;
      });
    }
  }

  /// Exibe SnackBar com mensagem
  void _showSnackBar(String message, Color backgroundColor) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      _getIcon(),
      color: _getColor(),
      size: widget.iconSize,
    );

    // Se está sincronizando, adiciona animação de rotação
    final Widget animatedIcon = _currentState == SyncState.syncing
        ? _RotatingIcon(child: icon)
        : icon;

    // Badge com contador de pendências
    final Widget badgedIcon = _pendingCount > 0
        ? Badge(
            label: Text('$_pendingCount'),
            backgroundColor: Colors.red,
            child: animatedIcon,
          )
        : animatedIcon;

    final Widget iconButton = IconButton(
      icon: badgedIcon,
      onPressed: _onTap,
      tooltip: widget.showTooltip ? _getTooltip() : null,
    );

    return iconButton;
  }
}

/// Widget auxiliar para rotacionar o ícone durante a sincronização
class _RotatingIcon extends StatefulWidget {
  final Widget child;

  const _RotatingIcon({required this.child});

  @override
  State<_RotatingIcon> createState() => _RotatingIconState();
}

class _RotatingIconState extends State<_RotatingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: widget.child,
    );
  }
}
