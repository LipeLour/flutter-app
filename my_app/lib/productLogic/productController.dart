import 'package:get/get.dart';
import '../models/product_model.dart';
import '../services/firebase_database_service.dart';

/// Controlador responsável por gerenciar as operações relacionadas aos produtos.
/// Usa Firebase Firestore em vez de SQLite.
class ProductController extends GetxController {
  final _db = FirebaseDatabaseService();

  // Lista reativa de produtos
  final produtos = <ProductModel>[].obs;

  // Estados reativos
  final carregando = false.obs;
  final erro = RxnString();
  final busca = ''.obs;

  /// Carrega todos os produtos ativos do banco (ou filtrados por nome)
  Future<void> carregarProdutos([String? filtro]) async {
    try {
      carregando.value = true;
      erro.value = null;

      final snapshot = await _db._firestore
          .collection('produtos')
          .where('ativo', isEqualTo: true)
          .get();

      final lista = snapshot.docs.map((d) {
        return ProductModel.fromFirestore(d);
      }).where((p) {
        final termo = (filtro ?? busca.value).toLowerCase();
        return termo.isEmpty || p.nome.toLowerCase().contains(termo);
      }).toList();

      produtos.assignAll(lista);
    } catch (e) {
      erro.value = 'Erro ao carregar produtos: $e';
    } finally {
      carregando.value = false;
    }
  }

  /// Validação simples dos campos de produto
  String? validarCampos({
    required String nome,
    required String precoTexto,
    required String estoqueTexto,
  }) {
    if (nome.trim().isEmpty) return 'O nome do produto é obrigatório.';
    final preco = double.tryParse(precoTexto.replaceAll(',', '.'));
    if (preco == null || preco < 0) return 'Preço inválido.';
    final estoque = int.tryParse(estoqueTexto);
    if (estoque == null || estoque < 0) return 'Estoque inválido.';
    return null;
  }

  /// Cria um novo produto no Firestore
  Future<bool> cadastrarProduto({
    required String nome,
    String? sku,
    required double preco,
    required int estoque,
    String? descricao,
  }) async {
    try {
      carregando.value = true;
      await _db.addProduct(
        nome: nome,
        sku: sku ?? '',
        preco: preco,
        estoque: estoque,
        descricao: descricao,
      );
      await carregarProdutos();
      return true;
    } catch (e) {
      erro.value = 'Erro ao cadastrar: $e';
      return false;
    } finally {
      carregando.value = false;
    }
  }

  /// Atualiza informações de um produto existente
  Future<bool> atualizarProduto(ProductModel produto) async {
    try {
      carregando.value = true;
      await _db.updateProduct(produto.id, produto.toMap());
      await carregarProdutos();
      return true;
    } catch (e) {
      erro.value = 'Erro ao atualizar: $e';
      return false;
    } finally {
      carregando.value = false;
    }
  }

  /// Exclui (soft delete) um produto
  Future<void> excluirProduto(String id) async {
    try {
      carregando.value = true;
      await _db.softDeleteProduct(id);
      await carregarProdutos();
    } catch (e) {
      erro.value = 'Erro ao excluir: $e';
    } finally {
      carregando.value = false;
    }
  }
}