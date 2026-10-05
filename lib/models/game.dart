import 'package:cloud_firestore/cloud_firestore.dart';

enum GameStatus { scheduled, inProgress, finalStatus }

enum PickSide { home, away }

class Game {
  final String id;
  final String homeTeam;
  final String awayTeam;
  final DateTime kickoffAt;
  final bool isLastGameOfWeek;
  final GameStatus status;
  final int? homeScore;
  final int? awayScore;
  final PickSide? winner;

  Game({
    required this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.isLastGameOfWeek,
    required this.status,
    this.homeScore,
    this.awayScore,
    this.winner,
  });

  bool get isFinal => status == GameStatus.finalStatus;

  factory Game.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Game(
      id: doc.id,
      homeTeam: d['homeTeam'] as String,
      awayTeam: d['awayTeam'] as String,
      kickoffAt: (d['kickoffAt'] as Timestamp).toDate(),
      isLastGameOfWeek: d['isLastGameOfWeek'] as bool? ?? false,
      status: switch (d['status']) {
        'final' => GameStatus.finalStatus,
        'in_progress' => GameStatus.inProgress,
        _ => GameStatus.scheduled,
      },
      homeScore: d['homeScore'] as int?,
      awayScore: d['awayScore'] as int?,
      winner: switch (d['winner']) {
        'home' => PickSide.home,
        'away' => PickSide.away,
        _ => null,
      },
    );
  }
}
