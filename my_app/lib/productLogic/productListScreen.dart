import 'package:corretor_prova/controller/productController.dart';
import 'package:corretor_prova/models/productModel.dart';
import 'package:corretor_prova/screens/productFormScreen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Tela responsável por exibir a lista de produtos.
/// Permite pesquisar, editar, excluir e adicionar novos produtos.
class ProductsListScreen extends StatelessWidget {
  ProductsListScreen({super.key});

  // Instancia o controlador de produtos usando GetX
  final c = Get.put(ProductController());

  @override
  Widget build(BuildContext context) {
    // Carrega a lista de produtos assim que a tela é aberta
    c.load();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produtos'),
        actions: [
          // Botão de atualizar (recarrega a lista)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => c.load(),
          ),
        ],
      ),

      // Corpo principal da tela
      body: Column(
        children: [
          // Campo de busca por nome ou SKU
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar por nome ou SKU...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                c.query.value = v; // Atualiza o texto de busca
                c.load(v);          // Recarrega a lista filtrando
              },
            ),
          ),

          // Lista reativa de produtos
          Expanded(
            child: Obx(() {
              // Exibe um indicador de carregamento
              if (c.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }

              // Exibe mensagem de erro, se houver
              if (c.error.value != null) {
                return Center(child: Text(c.error.value!));
              }

              // Exibe mensagem se não houver produtos
              if (c.products.isEmpty) {
                return const Center(child: Text('Nenhum produto encontrado.'));
              }

              // Lista de produtos
              return ListView.separated(
                itemCount: c.products.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final Product p = c.products[i];

                  // Cada item da lista é um ListTile
                  return ListTile(
                    title: Text('${p.name}  (Estoque: ${p.stock})'),
                    subtitle: Text(
                      'SKU: ${p.sku ?? '-'}  •  R\$ ${p.price.toStringAsFixed(2)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Botão para editar produto
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: 'Editar',
                          onPressed: () async {
                            final updated = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProductFormScreen(product: p),
                              ),
                            );
                            if (updated == true) c.load(); // Recarrega lista
                          },
                        ),

                        // Botão para excluir produto
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: 'Excluir',
                          onPressed: () => _confirmDelete(context, c, p),
                        ),
                      ],
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),

      // Botão flutuante para adicionar novo produto
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProductFormScreen()),
          );
          if (created == true) c.load(); // Recarrega lista após criação
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Função auxiliar que exibe um diálogo de confirmação antes de excluir o produto
  void _confirmDelete(BuildContext context, ProductController c, Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir produto'),
        content: Text('Confirmar exclusão de "${p.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    // Se o usuário confirmou, remove o produto
    if (ok == true && p.id != null) {
      await c.remove(p.id!);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto excluído.')),
      );
    }
  }
}