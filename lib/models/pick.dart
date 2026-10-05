import 'package:cloud_firestore/cloud_firestore.dart';
import 'game.dart';

class WeekPicks {
  final String uid;
  final Map<String, PickSide> selections;
  final int? tiebreakerGuess;

  WeekPicks({required this.uid, required this.selections, this.tiebreakerGuess});

  factory WeekPicks.empty(String uid) => WeekPicks(uid: uid, selections: {});

  Map<String, dynamic> toFirestore() => {
        'selections': selections.map((id, s) => MapEntry(id, s == PickSide.home ? 'home' : 'away')),
        'tiebreakerGuess': tiebreakerGuess,
        'submittedAt': FieldValue.serverTimestamp(),
      };

  factory WeekPicks.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final raw = (d['selections'] as Map<String, dynamic>? ?? {});
    return WeekPicks(
      uid: doc.id,
      selections: raw.map((id, s) => MapEntry(id, s == 'home' ? PickSide.home : PickSide.away)),
      tiebreakerGuess: d['tiebreakerGuess'] as int?,
    );
  }
}

class WeekResult {
  final String uid;
  final int correctCount;
  final int? tiebreakerDiff;
  final int rank;
  final bool isWeekWinner;

  WeekResult({
    required this.uid,
    required this.correctCount,
    required this.rank,
    this.tiebreakerDiff,
    this.isWeekWinner = false,
  });

  factory WeekResult.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return WeekResult(
      uid: doc.id,
      correctCount: d['correctCount'] as int? ?? 0,
      tiebreakerDiff: d['tiebreakerDiff'] as int?,
      rank: d['rank'] as int? ?? 0,
      isWeekWinner: d['isWeekWinner'] as bool? ?? false,
    );
  }
}
