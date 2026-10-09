import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/game.dart';
import '../models/pool.dart';
import '../models/week.dart';

class PoolService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _pools => _db.collection('pools');

  Stream<List<Pool>> watchMyPools(String uid) => _pools
      .where('memberUids', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs.map(Pool.fromFirestore).toList());

  Stream<Pool> watchPool(String poolId) => _pools
      .doc(poolId)
      .snapshots()
      .where((d) => d.exists) // ignore the snapshot that arrives when the pool is deleted
      .map(Pool.fromFirestore);

  /// Permanently deletes a pool and everything under it. Commissioner only (rules enforce it).
  ///
  /// Firestore does not delete subcollections with their parent, so this removes every
  /// week, game, pick and result first, and the pool document last. If it fails partway
  /// (e.g. network drop) the pool document is still there, so you can simply run it again.
  Future<void> deletePool(Pool pool) async {
    final poolRef = _pools.doc(pool.id);
    final refs = <DocumentReference<Map<String, dynamic>>>[];

    for (final uid in pool.memberUids) {
      refs.add(poolRef.collection('standings').doc(uid));
    }

    final weeks = await poolRef.collection('weeks').get();
    for (final week in weeks.docs) {
      final games = await week.reference.collection('games').get();
      refs.addAll(games.docs.map((g) => g.reference));
      // Pick/result doc IDs are member uids, so no need to read other players' picks.
      for (final uid in pool.memberUids) {
        refs.add(week.reference.collection('picks').doc(uid));
        refs.add(week.reference.collection('results').doc(uid));
      }
      refs.add(week.reference);
    }

    // One delete per document, a few in parallel.
    const chunk = 20;
    for (var i = 0; i < refs.length; i += chunk) {
      await Future.wait(
        refs.sublist(i, i + chunk > refs.length ? refs.length : i + chunk).map((r) => r.delete()),
      );
    }

    await poolRef.delete();
  }

  /// Creates the pool. The sync worker notices it on its next run and builds
  /// the season's weeks and games (usually within ~15 minutes).
  Future<String> createPool({
    required String name,
    required int season,
    required String uid,
  }) async {
    final ref = await _pools.add({
      'name': name,
      'season': season,
      'commissionerUid': uid,
      'memberUids': [uid],
    });
    return ref.id;
  }

  /// Joining is a rule-checked write: a user may only add their own uid.
  Future<void> joinPool(String poolId, String uid) =>
      _pools.doc(poolId).update({
        'memberUids': FieldValue.arrayUnion([uid]),
      });

  Stream<List<Week>> watchWeeks(String poolId) => _pools
      .doc(poolId)
      .collection('weeks')
      .orderBy('weekNumber')
      .snapshots()
      .map((s) => s.docs.map(Week.fromFirestore).toList());

  Stream<Week> watchWeek(String poolId, String weekId) => _pools
      .doc(poolId)
      .collection('weeks')
      .doc(weekId)
      .snapshots()
      .map(Week.fromFirestore);

  /// One-shot read of a week's games, ordered by kickoff.
  Future<List<Game>> fetchGames(String poolId, String weekId) async {
    final s = await _pools
        .doc(poolId)
        .collection('weeks')
        .doc(weekId)
        .collection('games')
        .orderBy('kickoffAt')
        .get();
    return s.docs.map(Game.fromFirestore).toList();
  }

  Stream<List<Game>> watchGames(String poolId, String weekId) => _pools
      .doc(poolId)
      .collection('weeks')
      .doc(weekId)
      .collection('games')
      .orderBy('kickoffAt')
      .snapshots()
      .map((s) => s.docs.map(Game.fromFirestore).toList());
}