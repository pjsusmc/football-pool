import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game.dart';
import '../models/pick.dart';
import '../models/week.dart';
import '../services/auth_service.dart';
import '../services/picks_service.dart';
import '../services/pool_service.dart';
import '../widgets/countdown_banner.dart';
import '../widgets/game_pick_card.dart';
import 'week_grid_screen.dart';

class WeekPicksScreen extends StatefulWidget {
  final String poolId;
  final String weekId;
  const WeekPicksScreen({super.key, required this.poolId, required this.weekId});

  @override
  State<WeekPicksScreen> createState() => _WeekPicksScreenState();
}

class _WeekPicksScreenState extends State<WeekPicksScreen> {
  final Map<String, PickSide> _selections = {};
  final _tiebreaker = TextEditingController();
  bool _saving = false;
  bool _hydrated = false;
  String? _error;

  @override
  void dispose() {
    _tiebreaker.dispose();
    super.dispose();
  }

  Future<void> _submit(Week week, List<Game> games) async {
    final guess = int.tryParse(_tiebreaker.text.trim());
    if (guess == null || guess < 0) {
      setState(() => _error = 'Enter your combined total-points guess for the last game.');
      return;
    }
    final missing = games.where((g) => !_selections.containsKey(g.id)).length;
    if (missing > 0) {
      setState(() => _error = 'You still have $missing game(s) without a pick.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<PicksService>().submitPicks(
            poolId: widget.poolId,
            week: week,
            picks: WeekPicks(
              uid: context.read<AuthService>().currentUser!.uid,
              selections: Map.of(_selections),
              tiebreakerGuess: guess,
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Picks submitted')));
      }
    } on WeekLockedException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not save picks: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pools = context.read<PoolService>();
    final picks = context.read<PicksService>();
    final uid = context.read<AuthService>().currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Picks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_view),
            tooltip: "Everyone's picks",
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WeekGridScreen(poolId: widget.poolId, weekId: widget.weekId),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<Week>(
        stream: pools.watchWeek(widget.poolId, widget.weekId),
        builder: (context, weekSnap) {
          if (!weekSnap.hasData) return const Center(child: CircularProgressIndicator());
          final week = weekSnap.data!;
          return StreamBuilder<List<Game>>(
            stream: pools.watchGames(widget.poolId, widget.weekId),
            builder: (context, gamesSnap) {
              if (!gamesSnap.hasData) return const Center(child: CircularProgressIndicator());
              final games = gamesSnap.data!;
              final lastGame = games.where((g) => g.isLastGameOfWeek).firstOrNull;
              return StreamBuilder<WeekPicks>(
                stream: picks.watchMyPicks(widget.poolId, widget.weekId, uid),
                builder: (context, pickSnap) {
                  if (pickSnap.hasData && !_hydrated) {
                    _selections.addAll(pickSnap.data!.selections);
                    final g = pickSnap.data!.tiebreakerGuess;
                    if (g != null) _tiebreaker.text = '$g';
                    _hydrated = true;
                  }
                  final locked = !week.isOpen;
                  return Column(
                    children: [
                      CountdownBanner(lockAt: week.lockAt, isLocked: locked),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(top: 8, bottom: 24),
                          children: [
                            for (final g in games)
                              GamePickCard(
                                game: g,
                                selected: _selections[g.id],
                                enabled: !locked,
                                onSelect: (s) => setState(() => _selections[g.id] = s),
                              ),
                            if (lastGame != null) _tiebreakerCard(lastGame, locked),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(_error!, style: const TextStyle(color: Colors.red)),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: FilledButton(
                                onPressed: (locked || _saving) ? null : () => _submit(week, games),
                                child: _saving
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2))
                                    : Text(locked ? 'Picks locked' : 'Submit picks'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _tiebreakerCard(Game g, bool locked) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tiebreaker: ${g.awayTeam} @ ${g.homeTeam}',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'Guess the combined points scored by both teams. If players tie on correct '
                'picks, the closest guess wins.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tiebreaker,
                enabled: !locked,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Total combined points',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      );
}