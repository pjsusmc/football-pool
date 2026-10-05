import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pool.dart';
import '../services/auth_service.dart';
import '../services/pool_service.dart';
import 'pool_home_screen.dart';

/// Landing screen after sign-in: list my pools, create one, or join by ID.
class PoolsScreen extends StatelessWidget {
  const PoolsScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create a pool'),
        content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Pool name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    final uid = context.read<AuthService>().currentUser!.uid;
    await context
        .read<PoolService>()
        .createPool(name: name.text.trim(), season: DateTime.now().year, uid: uid);
  }

  Future<void> _join(BuildContext context) async {
    final id = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join a pool'),
        content: TextField(controller: id, decoration: const InputDecoration(labelText: 'Pool ID')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Join')),
        ],
      ),
    );
    if (ok != true || id.text.trim().isEmpty || !context.mounted) return;
    try {
      await context.read<PoolService>().joinPool(id.text.trim());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not join: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final uid = auth.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Pools'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: auth.signOut, tooltip: 'Sign out'),
        ],
      ),
      body: StreamBuilder<List<Pool>>(
        stream: context.read<PoolService>().watchMyPools(uid),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final pools = snap.data!;
          if (pools.isEmpty) {
            return const Center(child: Text('Create a pool or join one with its ID.'));
          }
          return ListView(
            children: [
              for (final p in pools)
                ListTile(
                  title: Text(p.name),
                  subtitle: Text('${p.season} · ${p.memberUids.length} members · ID: ${p.id}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => PoolHomeScreen(poolId: p.id)),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'join',
            onPressed: () => _join(context),
            icon: const Icon(Icons.group_add),
            label: const Text('Join'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'create',
            onPressed: () => _create(context),
            icon: const Icon(Icons.add),
            label: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
