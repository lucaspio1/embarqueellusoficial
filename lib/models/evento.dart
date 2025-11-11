class Evento {
  final String id;
  final DateTime timestamp;
  final String tipoEvento;
  final String? inicioViagem;
  final String? fimViagem;
  final Map<String, dynamic> dados;
  final bool processado;

  Evento({
    required this.id,
    required this.timestamp,
    required this.tipoEvento,
    this.inicioViagem,
    this.fimViagem,
    required this.dados,
    this.processado = false,
  });

  factory Evento.fromJson(Map<String, dynamic> json) {
    return Evento(
      id: json['id'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'].toString())
          : DateTime.now(),
      tipoEvento: json['tipo_evento'] ?? '',
      inicioViagem: json['inicio_viagem'],
      fimViagem: json['fim_viagem'],
      dados: json['dados'] ?? {},
      processado: json['processado'] == 'SIM',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'tipo_evento': tipoEvento,
      'inicio_viagem': inicioViagem,
      'fim_viagem': fimViagem,
      'dados': dados,
      'processado': processado ? 'SIM' : 'NAO',
    };
  }

  @override
  String toString() {
    return 'Evento{id: $id, tipo: $tipoEvento, timestamp: $timestamp, processado: $processado}';
  }
}
