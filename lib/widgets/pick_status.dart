import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/pool.dart';
import '../models/week.dart';
import '../services/auth_service.dart';
import '../services/picks_service.dart';
import '../services/pool_service.dart';

/// Shows how many players have made picks for a week ("4 of 8 have made picks"), reminds you
/// if you haven't picked yet, and lets the commissioner see who is still missing.
/// It only uses the "has submitted" markers, never anyone's actual picks.
class PickStatus extends StatelessWidget {
  final String poolId;
  final Week week;

  /// When set, the reminder shows a "Make picks" button that calls this.
  final VoidCallback? onOpenPicks;
  const PickStatus({super.key, required this.poolId, required this.week, this.onOpenPicks});

  @override
  Widget build(BuildContext context) {
    final pools = context.read<PoolService>();
    final picks = context.read<PicksService>();
    final me = context.read<AuthService>().currentUser?.uid;

    return StreamBuilder<Pool>(
      stream: pools.watchPool(poolId),
      builder: (context, poolSnap) {
        return StreamBuilder<Set<String>>(
          stream: picks.watchSubmittedUids(poolId, week.id),
          builder: (context, subSnap) {
            if (!poolSnap.hasData || !subSnap.hasData) return const SizedBox.shrink();
            final pool = poolSnap.data!;
            final submitted = subSnap.data!;
            final total = pool.memberUids.length;
            final done = pool.memberUids.where(submitted.contains).length;
            final iMadePicks = me != null && submitted.contains(me);
            final needsReminder = week.isOpen && me != null && !iMadePicks;
            final isCommissioner = pool.commissionerUid == me;
            final missing = pool.memberUids.where((u) => !submitted.contains(u)).toList();
            final theme = Theme.of(context);

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: needsReminder ? Colors.amber.shade100 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: needsReminder ? Colors.amber.shade700 : Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (needsReminder) ...[
                    Row(children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text("You haven't made your ${week.title} picks yet",
                            style: theme.textTheme.titleSmall?.copyWith(color: Colors.black87)),
                      ),
                    ]),
                    Padding(
                      padding: const EdgeInsets.only(left: 32, top: 2),
                      child: Text(
                        'Picks lock ${DateFormat('EEE MMM d, h:mm a').format(week.lockAt.toLocal())}',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.black87),
                      ),
                    ),
                    if (onOpenPicks != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 32, top: 8),
                        child: FilledButton(onPressed: onOpenPicks, child: const Text('Make my picks')),
                      ),
                    const SizedBox(height: 8),
                  ] else if (iMadePicks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Text("You're in for ${week.title}",
                            style: theme.textTheme.titleSmall?.copyWith(color: Colors.black87)),
                      ]),
                    ),
                  Row(children: [
                    const Icon(Icons.groups_outlined, size: 20, color: Colors.black87),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('$done of $total have made picks',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600, color: Colors.black87)),
                    ),
                    if (isCommissioner && missing.isNotEmpty)
                      TextButton(
                        onPressed: () => _showMissing(context, week.title, missing),
                        child: const Text("Who hasn't picked?"),
                      ),
                  ]),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showMissing(BuildContext context, String weekTitle, List<String> missing) {
    final auth = context.read<AuthService>();
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Haven't picked for $weekTitle"),
        content: SizedBox(
          width: 320,
          child: FutureBuilder<Map<String, String>>(
            future: auth.displayNames(missing),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
              }
              final names = missing.map((u) => snap.data![u] ?? 'Player').toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final n in names)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        const Icon(Icons.person_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(n)),
                      ]),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }
}
