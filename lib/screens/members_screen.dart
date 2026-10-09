import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pool.dart';
import '../services/auth_service.dart';
import '../services/pool_service.dart';

/// Lists everyone in the pool. The commissioner can remove a player (e.g. a test account).
class MembersScreen extends StatelessWidget {
  final String poolId;
  const MembersScreen({super.key, required this.poolId});

  Future<void> _confirmRemove(BuildContext context, Pool pool, String uid, String name) async {
    final service = context.read<PoolService>();
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $name?'),
        content: Text(
          'This deletes $name\'s picks and results for every week in "${pool.name}" and removes '
          'them from the pool. It cannot be undone.\n\n'
          'Their login account is not deleted, and they could join again with the pool ID.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    messenger.showSnackBar(SnackBar(content: Text('Removing $name…')));
    try {
      await service.removeMember(pool, uid);
      messenger.showSnackBar(SnackBar(content: Text('$name was removed')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not remove $name: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pools = context.read<PoolService>();
    final auth = context.read<AuthService>();
    final me = auth.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: StreamBuilder<Pool>(
        stream: pools.watchPool(poolId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: SelectableText('Could not load members:\n${snap.error}',
                  style: const TextStyle(color: Colors.red)),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final pool = snap.data!;
          final iAmCommissioner = pool.commissionerUid == me;

          return FutureBuilder<Map<String, String>>(
            future: auth.displayNames(pool.memberUids),
            builder: (context, nameSnap) {
              final names = nameSnap.data ?? const <String, String>{};
              final uids = [...pool.memberUids]
                ..sort((a, b) => (names[a] ?? '').toLowerCase().compareTo((names[b] ?? '').toLowerCase()));

              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('${uids.length} member${uids.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  for (final uid in uids)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(names[uid] ?? '…'),
                      subtitle: uid == pool.commissionerUid
                          ? const Text('Commissioner')
                          : (uid == me ? const Text('You') : null),
                      // Only the commissioner can remove people, and not themselves.
                      trailing: (iAmCommissioner && uid != pool.commissionerUid)
                          ? IconButton(
                              icon: const Icon(Icons.person_remove_outlined),
                              tooltip: 'Remove from pool',
                              onPressed: () => _confirmRemove(context, pool, uid, names[uid] ?? 'this player'),
                            )
                          : null,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}