import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pick.dart';
import '../models/week.dart';
import '../services/auth_service.dart';
import '../services/picks_service.dart';
import '../services/pool_service.dart';
import 'player_stats_screen.dart';

class StandingsScreen extends StatelessWidget {
  final String poolId;
  const StandingsScreen({super.key, required this.poolId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Standings'),
          bottom: const TabBar(tabs: [Tab(text: 'Season'), Tab(text: 'By week')]),
        ),
        body: StreamBuilder<List<Week>>(
          stream: context.read<PoolService>().watchWeeks(poolId),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SelectableText('Could not load weeks:\n${snap.error}',
                      style: const TextStyle(color: Colors.red)),
                ),
              );
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final scored = snap.data!.where((w) => w.status == WeekStatus.scored).toList();
            if (scored.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No weeks scored yet. A week is scored once its last game is final.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return TabBarView(children: [
              _SeasonView(poolId: poolId, weeks: scored),
              _WeekView(poolId: poolId, weeks: scored),
            ]);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Season tab

class _SeasonRow {
  final String uid;
  String name = '';
  int total = 0; // total correct picks across scored weeks
  int wins = 0; // weeks won (incl. tiebreaker)
  int weeks = 0; // scored weeks this player has a result for
  _SeasonRow(this.uid);
}

class _SeasonView extends StatefulWidget {
  final String poolId;
  final List<Week> weeks;
  const _SeasonView({required this.poolId, required this.weeks});

  @override
  State<_SeasonView> createState() => _SeasonViewState();
}

class _SeasonViewState extends State<_SeasonView> {
  late Future<List<_SeasonRow>> _future;

  List<String> _ids(List<Week> weeks) => weeks.map((w) => w.id).toList();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _SeasonView old) {
    super.didUpdateWidget(old);
    // Reload only when a new week gets scored.
    if (!listEquals(_ids(old.weeks), _ids(widget.weeks))) _future = _load();
  }

  Future<List<_SeasonRow>> _load() async {
    final picks = context.read<PicksService>();
    final auth = context.read<AuthService>();

    final byWeek = await picks.fetchResultsForWeeks(widget.poolId, _ids(widget.weeks));
    final rows = <String, _SeasonRow>{};
    for (final results in byWeek.values) {
      for (final r in results) {
        final row = rows.putIfAbsent(r.uid, () => _SeasonRow(r.uid));
        row.total += r.correctCount;
        row.weeks += 1;
        if (r.isWeekWinner) row.wins += 1;
      }
    }

    final names = await auth.displayNames(rows.keys);
    for (final row in rows.values) {
      row.name = names[row.uid] ?? 'Player';
    }

    final list = rows.values.toList()
      ..sort((a, b) {
        if (b.total != a.total) return b.total.compareTo(a.total);
        if (b.wins != a.wins) return b.wins.compareTo(a.wins);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthService>().currentUser?.uid;
    return FutureBuilder<List<_SeasonRow>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText('Could not load season standings:\n${snap.error}',
                  style: const TextStyle(color: Colors.red)),
            ),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const Center(child: Text('No results yet.'));

        // Players level on total AND week wins share a rank.
        final ranks = <int>[];
        for (var i = 0; i < rows.length; i++) {
          final tied = i > 0 && rows[i].total == rows[i - 1].total && rows[i].wins == rows[i - 1].wins;
          ranks.add(tied ? ranks[i - 1] : i + 1);
        }

        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Ranked by total correct picks, then weeks won. '
                '${widget.weeks.length} week(s) scored.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (var i = 0; i < rows.length; i++)
              ListTile(
                tileColor: rows[i].uid == me
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlayerStatsScreen(
                    poolId: widget.poolId,
                    uid: rows[i].uid,
                    name: rows[i].name,
                    weeks: widget.weeks,
                  ),
                )),
                leading: CircleAvatar(child: Text('${ranks[i]}')),
                title: Text(
                  rows[i].name,
                  style: TextStyle(
                      fontWeight: rows[i].uid == me ? FontWeight.bold : FontWeight.normal),
                ),
                subtitle: Text(
                  '${rows[i].wins} week win${rows[i].wins == 1 ? '' : 's'} · '
                  '${rows[i].weeks} week${rows[i].weeks == 1 ? '' : 's'} played',
                ),
                trailing: Text('${rows[i].total} pts',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------- By-week tab

class _WeekView extends StatefulWidget {
  final String poolId;
  final List<Week> weeks; // scored weeks only
  const _WeekView({required this.poolId, required this.weeks});

  @override
  State<_WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<_WeekView> {
  String? _weekId;

  @override
  Widget build(BuildContext context) {
    final picks = context.read<PicksService>();
    final auth = context.read<AuthService>();
    final me = auth.currentUser?.uid;

    if (_weekId == null || !widget.weeks.any((w) => w.id == _weekId)) {
      _weekId = widget.weeks.last.id;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButton<String>(
            value: _weekId,
            isExpanded: true,
            items: [
              for (final w in widget.weeks)
                DropdownMenuItem(value: w.id, child: Text(w.title)),
            ],
            onChanged: (v) => setState(() => _weekId = v),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<WeekResult>>(
            stream: picks.watchResults(widget.poolId, _weekId!),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: SelectableText('Could not load results:\n${snap.error}',
                      style: const TextStyle(color: Colors.red)),
                );
              }
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
                          tileColor: r.uid == me
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PlayerStatsScreen(
                              poolId: widget.poolId,
                              uid: r.uid,
                              name: names[r.uid] ?? 'Player',
                              weeks: widget.weeks,
                            ),
                          )),
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
  }
}