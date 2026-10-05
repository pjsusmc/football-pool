import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/pool.dart';
import '../models/week.dart';
import '../services/pool_service.dart';
import 'standings_screen.dart';
import 'week_picks_screen.dart';

class PoolHomeScreen extends StatelessWidget {
  final String poolId;
  const PoolHomeScreen({super.key, required this.poolId});

  @override
  Widget build(BuildContext context) {
    final service = context.read<PoolService>();
    final fmt = DateFormat('EEE MMM d, h:mm a');
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<Pool>(
          stream: service.watchPool(poolId),
          builder: (_, snap) => Text(snap.data?.name ?? 'Pool'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard),
            tooltip: 'Standings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StandingsScreen(poolId: poolId)),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Week>>(
        stream: service.watchWeeks(poolId),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final weeks = snap.data!;
          if (weeks.isEmpty) {
            return const Center(child: Text('Weeks are still being set up. Check back shortly.'));
          }
          return ListView(
            children: [
              for (final w in weeks)
                ListTile(
                  title: Text('Week ${w.weekNumber}'),
                  subtitle: Text(w.isOpen
                      ? 'Open · picks lock ${fmt.format(w.lockAt.toLocal())}'
                      : w.status == WeekStatus.scored
                          ? 'Final'
                          : 'Locked'),
                  trailing: Icon(w.isOpen ? Icons.edit : Icons.lock,
                      color: w.isOpen ? Colors.green : Colors.grey),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => WeekPicksScreen(poolId: poolId, weekId: w.id)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
