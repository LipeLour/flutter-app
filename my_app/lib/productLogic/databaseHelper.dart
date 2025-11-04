import 'package:cloud_firestore/cloud_firestore.dart';

/// Classe responsável por gerenciar a comunicação com o Firebase Firestore.
/// Reescrita com base em uma lógica de cadastro de produtos e usuários.
class FirebaseDatabaseService {
  // Instância única (Singleton)
  static final FirebaseDatabaseService _instance =
      FirebaseDatabaseService._internal();

  factory FirebaseDatabaseService() => _instance;
  FirebaseDatabaseService._internal();

  /// Referência principal do banco
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --------------------------
  // USUÁRIOS
  // --------------------------

  /// Adiciona um novo usuário no banco Firestore
  Future<void> addUser({
    required String uid,
    required String nome,
    required String email,
    String? avatarUrl,
    bool googleUser = false,
    String role = 'aluno',
    String? turmaId,
  }) async {
    await _firestore.collection('usuarios').doc(uid).set({
      'nome': nome,
      'email': email,
      'avatarUrl': avatarUrl,
      'googleUser': googleUser,
      'role': role,
      'turmaId': turmaId,
      'criadoEm': FieldValue.serverTimestamp(),
    });
  }

  /// Atualiza informações do usuário
  Future<void> updateUser(String uid, Map<String, dynamic> dados) async {
    await _firestore.collection('usuarios').doc(uid).update(dados);
  }

  /// Busca um usuário pelo UID
  Future<DocumentSnapshot> getUser(String uid) async {
    return await _firestore.collection('usuarios').doc(uid).get();
  }

  // --------------------------
  // PRODUTOS
  // --------------------------

  /// Cadastra um novo produto
  Future<void> addProduct({
    required String nome,
    required String sku,
    required double preco,
    required int estoque,
    String? descricao,
  }) async {
    final produto = {
      'nome': nome,
      'sku': sku,
      'preco': preco,
      'estoque': estoque,
      'descricao': descricao,
      'criadoEm': FieldValue.serverTimestamp(),
      'atualizadoEm': FieldValue.serverTimestamp(),
      'ativo': true,
    };

    await _firestore.collection('produtos').add(produto);
  }

  /// Atualiza um produto existente
  Future<void> updateProduct(String produtoId, Map<String, dynamic> dados) async {
    dados['atualizadoEm'] = FieldValue.serverTimestamp();
    await _firestore.collection('produtos').doc(produtoId).update(dados);
  }

  /// Marca um produto como excluído (soft delete)
  Future<void> softDeleteProduct(String produtoId) async {
    await _firestore.collection('produtos').doc(produtoId).update({
      'ativo': false,
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
  }

  /// Lista todos os produtos ativos
  Stream<QuerySnapshot> getActiveProducts() {
    return _firestore
        .collection('produtos')
        .where('ativo', isEqualTo: true)
        .snapshots();
  }
}