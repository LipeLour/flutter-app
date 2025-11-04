import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/product_controller.dart';
import '../models/product_model.dart';

/// Tela de cadastro e edição de produtos.
/// Reescrita para funcionar com o Firebase Firestore e GetX.
class ProductFormScreen extends StatefulWidget {
  final ProductModel? produto;

  const ProductFormScreen({super.key, this.produto});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

/// Campos do formulário encapsulados em uma classe auxiliar
class _ProductFormFields {
  final nomeCtrl = TextEditingController();
  final skuCtrl = TextEditingController();
  final precoCtrl = TextEditingController();
  final estoqueCtrl = TextEditingController();
  final descricaoCtrl = TextEditingController();

  void dispose() {
    nomeCtrl.dispose();
    skuCtrl.dispose();
    precoCtrl.dispose();
    estoqueCtrl.dispose();
    descricaoCtrl.dispose();
  }
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final controller = Get.find<ProductController>();
  final form = _ProductFormFields();

  @override
  void initState() {
    super.initState();
    final produto = widget.produto;
    if (produto != null) {
      form.nomeCtrl.text = produto.nome;
      form.skuCtrl.text = produto.sku;
      form.precoCtrl.text = produto.preco.toStringAsFixed(2);
      form.estoqueCtrl.text = produto.estoque.toString();
      form.descricaoCtrl.text = produto.descricao ?? '';
    }
  }

  @override
  void dispose() {
    form.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.produto != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(editando ? 'Editar produto' : 'Novo produto'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: form.nomeCtrl,
              decoration: const InputDecoration(labelText: 'Nome *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: form.skuCtrl,
              decoration: const InputDecoration(labelText: 'Código SKU'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: form.precoCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Preço (R\$) *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: form.estoqueCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Estoque *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: form.descricaoCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Descrição'),
            ),
            const SizedBox(height: 20),
            Obx(
              () => ElevatedButton.icon(
                icon: controller.carregando.value
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label:
                    Text(editando ? 'Salvar alterações' : 'Cadastrar produto'),
                onPressed: controller.carregando.value
                    ? null
                    : () async {
                        // Validação de campos
                        final erro = controller.validarCampos(
                          nome: form.nomeCtrl.text,
                          precoTexto: form.precoCtrl.text,
                          estoqueTexto: form.estoqueCtrl.text,
                        );
                        if (erro != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(erro)),
                          );
                          return;
                        }

                        final preco = double.parse(
                            form.precoCtrl.text.replaceAll(',', '.'));
                        final estoque = int.parse(form.estoqueCtrl.text);

                        if (editando) {
                          // Atualização de produto existente
                          final produtoAtualizado = ProductModel(
                            id: widget.produto!.id,
                            nome: form.nomeCtrl.text.trim(),
                            sku: form.skuCtrl.text.trim(),
                            preco: preco,
                            estoque: estoque,
                            descricao: form.descricaoCtrl.text.trim(),
                            ativo: true,
                          );

                          final ok = await controller
                              .atualizarProduto(produtoAtualizado);
                          if (ok && mounted) Navigator.pop(context, true);
                        } else {
                          // Criação de novo produto
                          final ok = await controller.cadastrarProduto(
                            nome: form.nomeCtrl.text.trim(),
                            sku: form.skuCtrl.text.trim(),
                            preco: preco,
                            estoque: estoque,
                            descricao: form.descricaoCtrl.text.trim(),
                          );
                          if (ok && mounted) Navigator.pop(context, true);
                        }
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}