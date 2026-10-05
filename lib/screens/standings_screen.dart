import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pick.dart';
import '../models/week.dart';
import '../services/auth_service.dart';
import '../services/picks_service.dart';
import '../services/pool_service.dart';

class StandingsScreen extends StatefulWidget {
  final String poolId;
  const StandingsScreen({super.key, required this.poolId});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> {
  String? _weekId;

  @override
  Widget build(BuildContext context) {
    final pools = context.read<PoolService>();
    final picks = context.read<PicksService>();
    final auth = context.read<AuthService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Weekly Results')),
      body: StreamBuilder<List<Week>>(
        stream: pools.watchWeeks(widget.poolId),
        builder: (context, weekSnap) {
          if (!weekSnap.hasData) return const Center(child: CircularProgressIndicator());
          final scored = weekSnap.data!.where((w) => w.status == WeekStatus.scored).toList();
          if (scored.isEmpty) return const Center(child: Text('No weeks scored yet.'));
          _weekId ??= scored.last.id;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButton<String>(
                  value: _weekId,
                  isExpanded: true,
                  items: [
                    for (final w in scored)
                      DropdownMenuItem(value: w.id, child: Text('Week ${w.weekNumber}')),
                  ],
                  onChanged: (v) => setState(() => _weekId = v),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<WeekResult>>(
                  stream: picks.watchResults(widget.poolId, _weekId!),
                  builder: (context, snap) {
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final results = snap.data!;
                    return FutureBuilder<Map<String, String>>(
                      future: auth.displayNames(results.map((r) => r.uid)),
                      builder: (context, nameSnap) {
                        final names = nameSnap.data ?? {};
                        return ListView(
                          children: [
                            for (final r in results)
                              ListTile(
                                leading: CircleAvatar(child: Text('${r.rank}')),
                                title: Text(names[r.uid] ?? '…'),
                                subtitle: r.tiebreakerDiff != null
                                    ? Text('Tiebreaker off by ${r.tiebreakerDiff}')
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (r.isWeekWinner)
                                      const Icon(Icons.emoji_events, color: Colors.amber),
                                    const SizedBox(width: 8),
                                    Text('${r.correctCount} pts'),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
