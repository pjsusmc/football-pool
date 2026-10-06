import 'package:cloud_firestore/cloud_firestore.dart';

enum WeekStatus { open, locked, scored }

class Week {
  final String id;
  final int weekNumber;
  final String? label; // e.g. "Wild Card"; null for regular-season weeks
  final DateTime lockAt;
  final DateTime firstKickoffAt;
  final WeekStatus status;

  Week({
    required this.id,
    required this.weekNumber,
    this.label,
    required this.lockAt,
    required this.firstKickoffAt,
    required this.status,
  });

  /// What to show in lists: "Week 5" or "Wild Card".
  String get title => label ?? 'Week $weekNumber';

  bool get isOpen => status == WeekStatus.open && DateTime.now().isBefore(lockAt);

  factory Week.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Week(
      id: doc.id,
      weekNumber: d['weekNumber'] as int,
      label: d['label'] as String?,
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