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
    // Marker so the pool screen can show how many people have picked (never reveals the picks).
    await _week(poolId, week.id)
        .collection('submissions')
        .doc(picks.uid)
        .set({'submittedAt': FieldValue.serverTimestamp()});
  }

  /// UIDs of everyone who has submitted picks for the week. Readable while the week is open.
  Stream<Set<String>> watchSubmittedUids(String poolId, String weekId) =>
      _week(poolId, weekId)
          .collection('submissions')
          .snapshots()
          .map((s) => s.docs.map((d) => d.id).toSet());

  Stream<List<WeekResult>> watchResults(String poolId, String weekId) =>
      _week(poolId, weekId)
          .collection('results')
          .orderBy('rank')
          .snapshots()
          .map((s) => s.docs.map(WeekResult.fromFirestore).toList());

  /// Number of games in a week (cheap aggregate count, not a full read).
  Future<int> fetchGameCount(String poolId, String weekId) async {
    final agg = await _week(poolId, weekId).collection('games').count().get();
    return agg.count ?? 0;
  }

  /// One player's picks for a week. Other players' picks are only readable once the week locks.
  Future<WeekPicks> fetchPicks(String poolId, String weekId, String uid) async {
    final d = await _week(poolId, weekId).collection('picks').doc(uid).get();
    return d.exists ? WeekPicks.fromFirestore(d) : WeekPicks.empty(uid);
  }

  /// One-shot read of the results for several weeks, used to build season totals.
  Future<Map<String, List<WeekResult>>> fetchResultsForWeeks(
    String poolId,
    List<String> weekIds,
  ) async {
    final out = <String, List<WeekResult>>{};
    await Future.wait(weekIds.map((id) async {
      final snap = await _week(poolId, id).collection('results').get();
      out[id] = snap.docs.map(WeekResult.fromFirestore).toList();
    }));
    return out;
  }
}
