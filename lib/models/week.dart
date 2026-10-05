import 'package:cloud_firestore/cloud_firestore.dart';

enum WeekStatus { open, locked, scored }

class Week {
  final String id;
  final int weekNumber;
  final DateTime lockAt;
  final DateTime firstKickoffAt;
  final WeekStatus status;

  Week({
    required this.id,
    required this.weekNumber,
    required this.lockAt,
    required this.firstKickoffAt,
    required this.status,
  });

  bool get isOpen => status == WeekStatus.open && DateTime.now().isBefore(lockAt);

  factory Week.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Week(
      id: doc.id,
      weekNumber: d['weekNumber'] as int,
      lockAt: (d['lockAt'] as Timestamp).toDate(),
      firstKickoffAt: (d['firstKickoffAt'] as Timestamp).toDate(),
      status: switch (d['status']) {
        'locked' => WeekStatus.locked,
        'scored' => WeekStatus.scored,
        _ => WeekStatus.open,
      },
    );
  }
}
