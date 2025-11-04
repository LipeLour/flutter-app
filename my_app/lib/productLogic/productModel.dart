import 'package:cloud_firestore/cloud_firestore.dart';

class ProductModel {
  final String id;
  final String nome;
  final String sku;
  final double preco;
  final int estoque;
  final String? descricao;
  final bool ativo;

  ProductModel({
    required this.id,
    required this.nome,
    required this.sku,
    required this.preco,
    required this.estoque,
    this.descricao,
    this.ativo = true,
  });

  factory ProductModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ProductModel(
      id: doc.id,
      nome: data['nome'] ?? '',
      sku: data['sku'] ?? '',
      preco: (data['preco'] ?? 0).toDouble(),
      estoque: (data['estoque'] ?? 0).toInt(),
      descricao: data['descricao'],
      ativo: data['ativo'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'sku': sku,
      'preco': preco,
      'estoque': estoque,
      'descricao': descricao,
      'ativo': ativo,
    };
  }
}