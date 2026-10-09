import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../invite.dart';
import '../models/pool.dart';
import '../models/week.dart';
import '../services/auth_service.dart';
import '../services/pool_service.dart';
import 'members_screen.dart';
import 'standings_screen.dart';
import 'week_picks_screen.dart';

class PoolHomeScreen extends StatelessWidget {
  final String poolId;
  const PoolHomeScreen({super.key, required this.poolId});

  Future<void> _confirmDelete(BuildContext context, Pool pool) async {
    final service = context.read<PoolService>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final typed = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Delete this pool?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently deletes "${pool.name}" for all ${pool.memberUids.length} '
                'member(s), including every pick and result. It cannot be undone.',
              ),
              const SizedBox(height: 12),
              const Text('Type the pool name to confirm:'),
              TextField(
                controller: typed,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: typed.text.trim() == pool.name ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    messenger.showSnackBar(const SnackBar(content: Text('Deleting pool…')));
    try {
      await service.deletePool(pool);
      nav.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Pool deleted')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete pool: $e')));
    }
  }

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
          StreamBuilder<Pool>(
            stream: service.watchPool(poolId),
            builder: (context, snap) {
              final pool = snap.data;
              if (pool == null) return const SizedBox.shrink();
              final uid = context.read<AuthService>().currentUser?.uid;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Anyone in the pool can invite others.
                  IconButton(
                    icon: const Icon(Icons.person_add_alt_1),
                    tooltip: 'Copy invite to send to friends',
                    onPressed: () => copyInvite(context, pool),
                  ),
                  // Only the commissioner sees the delete button.
                  if (pool.commissionerUid == uid)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete pool',
                      onPressed: () => _confirmDelete(context, pool),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.group),
            tooltip: 'Members',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MembersScreen(poolId: poolId)),
            ),
          ),
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
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Setting up the season. Weeks appear automatically within about '
                  '15 minutes of creating the pool.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              for (final w in weeks)
                ListTile(
                  title: Text(w.title),
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
              // Playoff rounds are added automatically once ESPN publishes the matchups.
              // Week 22 is the Super Bowl, the last round, so stop showing the note once it exists.
              if (!weeks.any((w) => w.weekNumber >= 22))
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: Text(
                    weeks.any((w) => w.weekNumber >= 19)
                        ? 'The remaining playoff rounds will appear here once their matchups are set.'
                        : 'Playoff rounds will appear here once the matchups are set.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).hintColor),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}