// lib/models/quarto.dart
class Quarto {
  final String? id;
  final String numeroQuarto;
  final String escola;
  final String nomeHospede;
  final String cpf;
  final String? inicioViagem;
  final String? fimViagem;

  Quarto({
    this.id,
    required this.numeroQuarto,
    required this.escola,
    required this.nomeHospede,
    required this.cpf,
    this.inicioViagem,
    this.fimViagem,
  });

  factory Quarto.fromMap(Map<String, dynamic> map) {
    return Quarto(
      id: map['id']?.toString(),
      numeroQuarto: (map['numero_quarto'] ?? '').toString(),
      escola: (map['escola'] ?? '').toString(),
      nomeHospede: (map['nome_hospede'] ?? '').toString(),
      cpf: (map['cpf'] ?? '').toString(),
      inicioViagem: map['inicio_viagem']?.toString(),
      fimViagem: map['fim_viagem']?.toString(),
    );
  }

  factory Quarto.fromJson(Map<String, dynamic> json) {
    return Quarto(
      id: json['id']?.toString(),
      numeroQuarto: (json['Quarto'] ?? json['numero_quarto'] ?? '').toString(),
      escola: (json['Escola'] ?? json['escola'] ?? '').toString(),
      nomeHospede: (json['Nome do Hóspede'] ?? json['nome_hospede'] ?? '').toString(),
      cpf: (json['CPF'] ?? json['cpf'] ?? '').toString(),
      inicioViagem: json['inicio_viagem']?.toString(),
      fimViagem: json['fim_viagem']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'numero_quarto': numeroQuarto,
      'escola': escola,
      'nome_hospede': nomeHospede,
      'cpf': cpf,
      'inicio_viagem': inicioViagem,
      'fim_viagem': fimViagem,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'Quarto': numeroQuarto,
      'Escola': escola,
      'Nome do Hóspede': nomeHospede,
      'CPF': cpf,
      'inicio_viagem': inicioViagem,
      'fim_viagem': fimViagem,
    };
  }

  @override
  String toString() {
    return 'Quarto(numeroQuarto: $numeroQuarto, escola: $escola, nomeHospede: $nomeHospede, cpf: $cpf)';
  }
}
