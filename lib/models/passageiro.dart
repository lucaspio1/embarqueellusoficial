// lib/models/passageiro.dart
class Passageiro {
  final String nome;
  final String idPasseio;
  final String turma;
  final String embarque;
  final String retorno;
  final String onibus;
  final String? cpf;
  final String? codigoPulseira;
  String? flowType;
  final String? inicioViagem;
  final String? fimViagem;

  Passageiro({
    required this.nome,
    required this.idPasseio,
    required this.turma,
    required this.embarque,
    required this.retorno,
    required this.onibus,
    this.cpf,
    this.codigoPulseira,
    this.flowType,
    this.inicioViagem,
    this.fimViagem,
  });

  factory Passageiro.fromMap(Map<String, dynamic> map) {
    return Passageiro(
      nome: (map['nome'] ?? '').toString(),
      idPasseio: (map['id_passeio'] ?? '').toString(),
      turma: (map['turma'] ?? '').toString(),
      embarque: (map['embarque'] ?? 'NÃO').toString(),
      retorno: (map['retorno'] ?? 'NÃO').toString(),
      onibus: (map['onibus'] ?? '').toString(),
      cpf: map['cpf']?.toString(),
      codigoPulseira: map['codigo_pulseira']?.toString(),
      inicioViagem: map['inicio_viagem']?.toString(),
      fimViagem: map['fim_viagem']?.toString(),
    );
  }

  factory Passageiro.fromJson(Map<String, dynamic> json) {
    return Passageiro(
      nome: (json['nome'] ?? '').toString(),
      idPasseio: (json['idPasseio'] ?? '').toString(),
      turma: (json['turma'] ?? '').toString(),
      embarque: (json['embarque'] ?? 'NÃO').toString(),
      retorno: (json['retorno'] ?? 'NÃO').toString(),
      onibus: (json['onibus'] ?? '').toString(),
      cpf: json['cpf']?.toString(),
      codigoPulseira: json['codigoPulseira']?.toString(),
      flowType: json['flowType']?.toString(),
      inicioViagem: json['inicioViagem']?.toString(),
      fimViagem: json['fimViagem']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nome': nome,
      'idPasseio': idPasseio,
      'turma': turma,
      'embarque': embarque,
      'retorno': retorno,
      'onibus': onibus,
      'cpf': cpf,
      'codigoPulseira': codigoPulseira,
      'flowType': flowType,
      'inicioViagem': inicioViagem,
      'fimViagem': fimViagem,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'id_passeio': idPasseio,
      'turma': turma,
      'embarque': embarque,
      'retorno': retorno,
      'onibus': onibus,
      'cpf': cpf,
      'codigo_pulseira': codigoPulseira,
      'inicio_viagem': inicioViagem,
      'fim_viagem': fimViagem,
    };
  }

  Passageiro copyWith({
    String? nome,
    String? idPasseio,
    String? turma,
    String? embarque,
    String? retorno,
    String? onibus,
    String? cpf,
    String? flowType,
    String? codigoPulseira,
    String? inicioViagem,
    String? fimViagem,
  }) {
    return Passageiro(
      nome: nome ?? this.nome,
      idPasseio: idPasseio ?? this.idPasseio,
      turma: turma ?? this.turma,
      embarque: embarque ?? this.embarque,
      retorno: retorno ?? this.retorno,
      onibus: onibus ?? this.onibus,
      cpf: cpf ?? this.cpf,
      flowType: flowType ?? this.flowType,
      codigoPulseira: codigoPulseira ?? this.codigoPulseira,
      inicioViagem: inicioViagem ?? this.inicioViagem,
      fimViagem: fimViagem ?? this.fimViagem,
    );
  }

  @override
  String toString() {
    return 'Passageiro(nome: $nome, cpf: $cpf, idPasseio: $idPasseio, turma: $turma, onibus: $onibus, embarque: $embarque, retorno: $retorno, pulseira: $codigoPulseira, inicioViagem: $inicioViagem, fimViagem: $fimViagem)';
  }
}