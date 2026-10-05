import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pick.dart';
import '../models/week.dart';

class WeekLockedException implements Exception {
  final String message;
  WeekLockedException(this.message);
  @override
  String toString() => message;
}

class PicksService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _week(String poolId, String weekId) =>
      _db.collection('pools').doc(poolId).collection('weeks').doc(weekId);

  Stream<WeekPicks> watchMyPicks(String poolId, String weekId, String uid) =>
      _week(poolId, weekId).collection('picks').doc(uid).snapshots().map(
            (d) => d.exists ? WeekPicks.fromFirestore(d) : WeekPicks.empty(uid),
          );

  /// Everyone's picks, only readable once the week has locked (see rules).
  Stream<List<WeekPicks>> watchAllPicks(String poolId, String weekId) =>
      _week(poolId, weekId)
          .collection('picks')
          .snapshots()
          .map((s) => s.docs.map(WeekPicks.fromFirestore).toList());

  Future<void> submitPicks({
    required String poolId,
    required Week week,
    required WeekPicks picks,
  }) async {
    if (!week.isOpen) {
      throw WeekLockedException('Picks for this week are locked.');
    }
    await _week(poolId, week.id).collection('picks').doc(picks.uid).set(picks.toFirestore());
  }

  Stream<List<WeekResult>> watchResults(String poolId, String weekId) =>
      _week(poolId, weekId)
          .collection('results')
          .orderBy('rank')
          .snapshots()
          .map((s) => s.docs.map(WeekResult.fromFirestore).toList());
}
