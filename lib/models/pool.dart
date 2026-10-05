import 'package:cloud_firestore/cloud_firestore.dart';

class Pool {
  final String id;
  final String name;
  final int season;
  final String commissionerUid;
  final List<String> memberUids;

  Pool({
    required this.id,
    required this.name,
    required this.season,
    required this.commissionerUid,
    required this.memberUids,
  });

  factory Pool.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Pool(
      id: doc.id,
      name: d['name'] as String,
      season: d['season'] as int,
      commissionerUid: d['commissionerUid'] as String,
      memberUids: List<String>.from(d['memberUids'] as List? ?? []),
    );
  }
}
