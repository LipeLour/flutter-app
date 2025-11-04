import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:corretor_prova/database/databaseHelper.dart';
import 'package:corretor_prova/models/productModel.dart';
import 'package:corretor_prova/repository/productRepository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ===============================================
/// REPOSITÓRIO LOCAL (SQLite)
/// ===============================================
class ProductRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<int> create(Product product) async {
    final db = await _dbHelper.database;
    return await db.insert(
      'products',
      product.copyWith(dirty: true).toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<Product>> getAll({String? q}) async {
    final db = await _dbHelper.database;
    final where = <String>['deleted = 0'];
    final args = <Object?>[];

    if ((q ?? '').trim().isNotEmpty) {
      where.add('(name LIKE ? OR sku LIKE ?)');
      args.addAll(['%$q%', '%$q%']);
    }

    final rows = await db.query(
      'products',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'updatedAt DESC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> getById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('products', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<Product?> getByRemoteId(String remoteId) async {
    final db = await _dbHelper.database;
    final rows =
        await db.query('products', where: 'remoteId = ?', whereArgs: [remoteId]);
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<int> update(Product product) async {
    if (product.id == null) throw ArgumentError('Produto sem ID para update.');
    final db = await _dbHelper.database;
    final updated = product.copyWith(updatedAt: DateTime.now(), dirty: true);
    return await db.update(
      'products',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> delete(int id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Soft delete + marca como sujo
    return await db.update(
      'products',
      {'deleted': 1, 'dirty': 1, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ===== Sincronização Local =====
  Future<void> upsertFromRemote(Product remote) async {
    final db = await _dbHelper.database;
    final existing = await getByRemoteId(remote.remoteId!);
    final data = remote.copyWith(dirty: false).toMap();
    if (existing == null) {
      await db.insert('products', data, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.update('products', data, where: 'id = ?', whereArgs: [existing.id]);
    }
  }

  Future<List<Product>> getDirty() async {
    final db = await _dbHelper.database;
    final rows = await db.query('products', where: 'dirty = 1');
    return rows.map(Product.fromMap).toList();
  }

  Future<void> markSynced(int id) async {
    final db = await _dbHelper.database;
    await db.update('products', {'dirty': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setRemoteId(int id, String remoteId) async {
    final db = await _dbHelper.database;
    await db.update('products', {'remoteId': remoteId, 'dirty': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> hardDelete(int id) async {
    final db = await _dbHelper.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> adjustStock({required int id, required int delta}) async {
    final db = await _dbHelper.database;
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    return await db.rawUpdate(
      '''
      UPDATE products
      SET stock = stock + ?, updatedAt = ?, dirty = 1
      WHERE id = ?
      ''',
      [delta, updatedAt, id],
    );
  }
}

/// ===============================================
/// REPOSITÓRIO REMOTO (Firebase Firestore)
/// ===============================================
class ProductRemoteRepository {
  final _fs = FirebaseFirestore.instance;

  String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('FirebaseAuth.currentUser == null (usuário não autenticado).');
    }
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _fs.collection('users').doc(_uid).collection('products');

  Future<String> create(Product p) async {
    final doc = await _col.add(p.toFirestore(_uid));
    return doc.id;
  }

  Future<void> upsert(Product p) async {
    if (p.remoteId == null) {
      final id = await create(p);
      await _col.doc(id).set(
        {'updatedAt': p.updatedAt.millisecondsSinceEpoch},
        SetOptions(merge: true),
      );
      return;
    }
    await _col.doc(p.remoteId).set(p.toFirestore(_uid), SetOptions(merge: true));
  }

  Future<void> deleteRemote(String remoteId) async {
    await _col.doc(remoteId).set(
      {'deleted': true, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
      SetOptions(merge: true),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAll() {
    return _col.orderBy('updatedAt', descending: true).snapshots();
  }

  Future<List<Product>> fetchAllOnce() async {
    final snap = await _col.get();
    return snap.docs
        .map((d) => Product.fromFirestore(d.data(), remoteId: d.id))
        .toList();
  }
}

/// ===============================================
/// SERVIÇO DE SINCRONIZAÇÃO (Local ↔ Remoto)
/// ===============================================
class ProductSyncService {
  final ProductRepository local;
  final ProductRemoteRepository remote;
  StreamSubscription? _connSub;
  StreamSubscription? _remoteSub;

  ProductSyncService({required this.local, required this.remote});

  Future<void> init() async {
    await pullFromRemote();

    _remoteSub = remote.watchAll().listen((snap) async {
      for (final change in snap.docChanges) {
        final data = change.doc.data();
        if (data == null) continue;
        final p = Product.fromFirestore(data, remoteId: change.doc.id);
        final current =
            p.remoteId == null ? null : await local.getByRemoteId(p.remoteId!);

        if (current == null || p.updatedAt.isAfter(current.updatedAt)) {
          if (p.deleted) {
            if (current?.id != null) {
              await local.hardDelete(current!.id!);
            }
          } else {
            await local.upsertFromRemote(p);
          }
        }
      }
    });

    _connSub = Connectivity().onConnectivityChanged.listen((status) async {
      if (status != ConnectivityResult.none) {
        await pushDirty();
      }
    });

    final now = await Connectivity().checkConnectivity();
    if (now != ConnectivityResult.none) {
      await pushDirty();
    }
  }

  Future<void> dispose() async {
    await _connSub?.cancel();
    await _remoteSub?.cancel();
  }

  Future<void> pullFromRemote() async {
    final all = await remote.fetchAllOnce();
    for (final p in all) {
      final current =
          p.remoteId == null ? null : await local.getByRemoteId(p.remoteId!);
      if (current == null || p.updatedAt.isAfter(current.updatedAt)) {
        if (p.deleted) {
          if (current?.id != null) await local.hardDelete(current!.id!);
        } else {
          await local.upsertFromRemote(p);
        }
      }
    }
  }

  Future<void> pushDirty() async {
    final dirty = await local.getDirty();
    for (final p in dirty) {
      if (p.deleted) {
        if (p.remoteId != null) {
          await remote.deleteRemote(p.remoteId!);
          if (p.id != null) await local.hardDelete(p.id!);
        } else {
          if (p.id != null) await local.hardDelete(p.id!);
        }
        continue;
      }

      await remote.upsert(p);
      await pullFromRemote();
      if (p.id != null && p.remoteId != null) {
        await local.markSynced(p.id!);
      }
    }
  }
}