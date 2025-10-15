class Passageiro {
  final String nome;
  final String idPasseio; // ✅ ID do passeio (ex: nome completo do evento)
  final String turma;
  final String embarque;
  final String retorno;
  final String onibus; // ✅ Ônibus do aluno
  final String? cpf; // ✅ Novo campo — chave primária para sincronização
  final String? codigoPulseira; // ✅ Código da pulseira (coluna K)
  String? flowType;

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
  });

  factory Passageiro.fromJson(Map<String, dynamic> json) {
    return Passageiro(
      nome: (json['nome'] ?? '').toString(),
      idPasseio: (json['idPasseio'] ?? '').toString(),
      turma: (json['turma'] ?? '').toString(),
      embarque: (json['embarque'] ?? 'NÃO').toString(),
      retorno: (json['retorno'] ?? 'NÃO').toString(),
      onibus: (json['onibus'] ?? '').toString(),
      cpf: (json['cpf'] ?? '').toString(), // ✅ Recebe do AppScript
      codigoPulseira: (json['codigoPulseira'] ?? '').toString(), // ✅ Recebe da planilha (coluna K)
      flowType: json['flowType']?.toString(),
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
    );
  }

  @override
  String toString() {
    return 'Passageiro(nome: $nome, cpf: $cpf, idPasseio: $idPasseio, turma: $turma, onibus: $onibus, embarque: $embarque, retorno: $retorno, pulseira: $codigoPulseira)';
  }
}
