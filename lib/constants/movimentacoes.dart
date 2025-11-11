/// Constantes de movimentação para o sistema de reconhecimento facial
class Movimentacoes {
  // ========== VALORES ARMAZENADOS NO BANCO ==========
  static const String quartoInicial = 'QUARTO'; // Valor inicial no cadastro
  static const String saiuDoQuarto = 'SAIU_DO_QUARTO';
  static const String voltouAoQuarto = 'VOLTOU_AO_QUARTO';
  static const String foiParaBalada = 'FOI_PARA_BALADA';

  // ========== LISTA DE TODAS AS MOVIMENTAÇÕES ==========
  static const List<String> todas = [
    saiuDoQuarto,
    voltouAoQuarto,
    foiParaBalada,
  ];

  // ========== INFORMAÇÕES PARA UI ==========
  static Map<String, MovimentacaoInfo> get info => {
        quartoInicial: MovimentacaoInfo(
          titulo: 'No Quarto',
          icone: '🏠',
          cor: 0xFF2196F3, // Colors.blue
        ),
        saiuDoQuarto: MovimentacaoInfo(
          titulo: 'Fora do Quarto',
          icone: '🚪',
          cor: 0xFFFF9800, // Colors.orange
        ),
        voltouAoQuarto: MovimentacaoInfo(
          titulo: 'Voltou ao Quarto',
          icone: '🏠',
          cor: 0xFF4CAF50, // Colors.green
        ),
        foiParaBalada: MovimentacaoInfo(
          titulo: 'Foi para Balada',
          icone: '🎉',
          cor: 0xFF9C27B0, // Colors.purple
        ),
      };

  // ========== HELPERS ==========
  static MovimentacaoInfo getInfo(String movimentacao) {
    return info[movimentacao.toUpperCase()] ??
        MovimentacaoInfo(
          titulo: movimentacao,
          icone: '❓',
          cor: 0xFF9E9E9E, // Colors.grey
        );
  }

  static bool isValid(String movimentacao) {
    final upper = movimentacao.toUpperCase();
    return upper == quartoInicial || todas.contains(upper);
  }
}

/// Informações de uma movimentação para exibição na UI
class MovimentacaoInfo {
  final String titulo;
  final String icone;
  final int cor; // Color value (0xFFRRGGBB)

  const MovimentacaoInfo({
    required this.titulo,
    required this.icone,
    required this.cor,
  });
}
