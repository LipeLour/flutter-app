// lib/repository/productRepository.dart

import 'package:meu_app/database/localDatabase.dart';
import 'package:meu_app/models/productModel.dart';
import 'package:sqflite/sqflite.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Repositório local responsável por gerenciar os produtos no banco SQLite.
/// Essa camada faz a ponte entre o banco e o controlador de produtos.
class ProductRepository {
  final _localDb = LocalDatabase.instance;

  /// Cria um novo produto no banco local
  Future<int> insertProduct(Product product) async {
    final db = await _localDb.database;
    return await db.insert(
      'products',
      product.copyWith(isSynced: false).toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Retorna todos os produtos, com filtro opcional de busca
  Future<List<Product>> getAll({String? search}) async {
    final db = await _localDb.database;
    final conditions = <String>['deleted = 0'];
    final args = <Object?>[];

    if ((search ?? '').trim().isNotEmpty) {
      conditions.add('(name LIKE ? OR sku LIKE ?)');
      args.addAll(['%$search%', '%$search%']);
    }

    final result = await db.query(
      'products',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'updatedAt DESC',
    );
    return result.map(Product.fromMap).toList();
  }

  /// Busca um produto pelo ID local
  Future<Product?> getById(int id) async {
    final db = await _localDb.database;
    final rows = await db.query('products', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// Busca um produto pelo ID remoto (Firebase)
  Future<Product?> getByRemoteId(String remoteId) async {
    final db = await _localDb.database;
    final rows = await db.query('products', where: 'remoteId = ?', whereArgs: [remoteId]);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// Atualiza um produto existente
  Future<int> update(Product product) async {
    if (product.id == null) throw ArgumentError('Produto sem ID não pode ser atualizado.');
    final db = await _localDb.database;
    final updated = product.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );
    return await db.update(
      'products',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Marca o produto como deletado (soft delete)
  Future<int> softDelete(int id) async {
    final db = await _localDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return await db.update(
      'products',
      {'deleted': 1, 'isSynced': 0, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Insere ou atualiza o produto local a partir do remoto (Firebase)
  Future<void> upsertFromRemote(Product remote) async {
    final db = await _localDb.database;
    final existing = await getByRemoteId(remote.remoteId!);
    final data = remote.copyWith(isSynced: true).toMap();

    if (existing == null) {
      await db.insert('products', data, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.update('products', data, where: 'id = ?', whereArgs: [existing.id]);
    }
  }

  /// Retorna todos os produtos que ainda não foram sincronizados
  Future<List<Product>> getPendingSync() async {
    final db = await _localDb.database;
    final rows = await db.query('products', where: 'isSynced = 0');
    return rows.map(Product.fromMap).toList();
  }

  /// Marca um produto como sincronizado
  Future<void> markAsSynced(int id) async {
    final db = await _localDb.database;
    await db.update('products', {'isSynced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  /// Define o ID remoto (Firebase) após a sincronização
  Future<void> setRemoteId(int id, String remoteId) async {
    final db = await _localDb.database;
    await db.update(
      'products',
      {'remoteId': remoteId, 'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Remove definitivamente um produto do banco local
  Future<void> hardDelete(int id) async {
    final db = await _localDb.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  /// Ajusta o estoque de um produto (ex: +1 ou -1)
  Future<int> updateStock({required int id, required int delta}) async {
    final db = await _localDb.database;
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    return await db.rawUpdate(
      '''
      UPDATE products
      SET stock = stock + ?, updatedAt = ?, isSynced = 0
      WHERE id = ?
      ''',
      [delta, updatedAt, id],
    );
  }
}

/// Repositório remoto responsável por integrar o app com o Firebase Firestore.
/// Cada usuário tem sua própria coleção de produtos.
class ProductRemoteRepository {
  final _firestore = FirebaseFirestore.instance;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Usuário não autenticado no Firebase.');
    return user.uid;
  }

  /// Referência para a coleção "products" dentro do usuário logado
  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('usuarios').doc(_userId).collection('meus_produtos');

  /// Cria um novo documento no Firestore
  Future<String> create(Product p) async {
    final doc = await _collection.add(p.toFirestore(_userId));
    return doc.id;
  }

  /// Atualiza ou cria um produto remoto (upsert)
  Future<void> upsert(Product p) async {
    if (p.remoteId == null) {
      final newId = await create(p);
      await _collection.doc(newId).set(
        {'updatedAt': p.updatedAt.millisecondsSinceEpoch},
        SetOptions(merge: true),
      );
      return;
    }
    await _collection.doc(p.remoteId).set(
      p.toFirestore(_userId),
      SetOptions(merge: true),
    );
  }

  /// Marca o produto como excluído remotamente (sem apagar de fato)
  Future<void> softDeleteRemote(String remoteId) async {
    await _collection.doc(remoteId).set(
      {'deleted': true, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
      SetOptions(merge: true),
    );
  }

  /// Observa em tempo real todas as alterações na coleção de produtos
  Stream<QuerySnapshot<Map<String, dynamic>>> watchAll() {
    return _collection.orderBy('updatedAt', descending: true).snapshots();
  }

  /// Busca todos os produtos de uma vez (sem stream)
  Future<List<Product>> fetchAllOnce() async {
    final snapshot = await _collection.get();
    return snapshot.docs
        .map((doc) => Product.fromFirestore(doc.data(), remoteId: doc.id))
        .toList();
  }
}