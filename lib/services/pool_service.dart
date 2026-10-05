import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

  Stream<Pool> watchPool(String poolId) =>
      _pools.doc(poolId).snapshots().map(Pool.fromFirestore);

  /// Creates the pool, then asks the backend to build the season's weeks.
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
    await FirebaseFunctions.instance
        .httpsCallable('initPoolSeason')
        .call({'poolId': ref.id});
    return ref.id;
  }

  Future<void> joinPool(String poolId) =>
      FirebaseFunctions.instance.httpsCallable('joinPool').call({'poolId': poolId});

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

  Stream<List<Game>> watchGames(String poolId, String weekId) => _pools
      .doc(poolId)
      .collection('weeks')
      .doc(weekId)
      .collection('games')
      .orderBy('kickoffAt')
      .snapshots()
      .map((s) => s.docs.map(Game.fromFirestore).toList());
}
