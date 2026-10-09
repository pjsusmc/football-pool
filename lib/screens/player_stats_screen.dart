import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game.dart';
import '../models/pick.dart';
import '../models/week.dart';
import '../services/picks_service.dart';
import '../services/pool_service.dart';

/// One player's season stats plus a week-by-week breakdown. Opened by tapping a name on the
/// Standings screen. Only scored weeks are included.
class PlayerStatsScreen extends StatefulWidget {
  final String poolId;
  final String uid;
  final String name;
  final List<Week> weeks; // scored weeks, oldest first
  const PlayerStatsScreen({
    super.key,
    required this.poolId,
    required this.uid,
    required this.name,
    required this.weeks,
  });

  @override
  State<PlayerStatsScreen> createState() => _PlayerStatsScreenState();
}

class _WeekRow {
  final Week week;
  final int games;
  final WeekResult mine;
  final int fieldSize; // players with a result that week
  _WeekRow(this.week, this.games, this.mine, this.fieldSize);

  /// Players must enter a tiebreaker guess to submit, so a missing guess means no picks were made.
  bool get played => mine.tiebreakerDiff != null;
}

class _Stats {
  final List<_WeekRow> rows;
  _Stats(this.rows);

  List<_WeekRow> get playedRows => rows.where((r) => r.played).toList();
  int get correct => playedRows.fold(0, (s, r) => s + r.mine.correctCount);
  int get gamesPlayed => playedRows.fold(0, (s, r) => s + r.games);
  int get wins => rows.where((r) => r.mine.isWeekWinner).length;

  _WeekRow? get best {
    final p = playedRows;
    if (p.isEmpty) return null;
    return p.reduce((a, b) => b.mine.correctCount > a.mine.correctCount ? b : a);
  }

  double? get avgMiss {
    final p = playedRows;
    if (p.isEmpty) return null;
    return p.fold<int>(0, (s, r) => s + r.mine.tiebreakerDiff!) / p.length;
  }
}

class _PlayerStatsScreenState extends State<PlayerStatsScreen> {
  late final Future<_Stats> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Stats> _load() async {
    final picks = context.read<PicksService>();
    final ids = widget.weeks.map((w) => w.id).toList();

    final results = await picks.fetchResultsForWeeks(widget.poolId, ids);
    final counts = await Future.wait(widget.weeks.map((w) => picks.fetchGameCount(widget.poolId, w.id)));

    final rows = <_WeekRow>[];
    for (var i = 0; i < widget.weeks.length; i++) {
      final week = widget.weeks[i];
      final all = results[week.id] ?? const <WeekResult>[];
      final mine = all.where((r) => r.uid == widget.uid).firstOrNull;
      // No result means the player wasn't in the pool yet that week.
      if (mine != null) rows.add(_WeekRow(week, counts[i], mine, all.length));
    }
    return _Stats(rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: FutureBuilder<_Stats>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText('Could not load stats:\n${snap.error}',
                    style: const TextStyle(color: Colors.red)),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final stats = snap.data!;
          if (stats.rows.isEmpty) {
            return const Center(child: Text('No scored weeks for this player yet.'));
          }
          return _body(context, stats);
        },
      ),
    );
  }

  Widget _tile(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, _Stats s) {
    final played = s.playedRows;
    final best = s.best;
    final accuracy = s.gamesPlayed > 0 ? '${(s.correct * 100 / s.gamesPlayed).round()}%' : '–';
    final avgCorrect = played.isNotEmpty ? (s.correct / played.length).toStringAsFixed(1) : '–';
    final avgMiss = s.avgMiss?.toStringAsFixed(1) ?? '–';

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _tile(context, '${s.correct}', 'Total correct picks'),
              _tile(context, accuracy, 'Pick accuracy'),
              _tile(context, '${s.wins}', 'Week wins'),
              _tile(context, '${played.length} of ${s.rows.length}', 'Weeks played'),
              _tile(context, avgCorrect, 'Avg correct per week'),
              _tile(context, avgMiss, 'Avg tiebreaker miss'),
              if (best != null)
                _tile(context, '${best.mine.correctCount} of ${best.games}', 'Best: ${best.week.title}'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text('Week by week', style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final r in s.rows.reversed)
          ExpansionTile(
            leading: r.mine.isWeekWinner
                ? const Icon(Icons.emoji_events, color: Colors.amber)
                : r.played
                    ? const Icon(Icons.check_circle_outline)
                    : const Icon(Icons.remove_circle_outline, color: Colors.grey),
            title: Text(r.week.title),
            subtitle: Text(
              r.played
                  ? '${r.mine.correctCount} of ${r.games} correct · rank ${r.mine.rank} of ${r.fieldSize}'
                  : 'Did not play · rank ${r.mine.rank} of ${r.fieldSize}',
            ),
            children: [
              if (r.played)
                _WeekDetail(poolId: widget.poolId, week: r.week, uid: widget.uid)
              else
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No picks were submitted for this round.'),
                ),
            ],
          ),
      ],
    );
  }
}

/// A player's pick-by-pick results for one week. Loads only when its tile is expanded.
class _WeekDetail extends StatefulWidget {
  final String poolId;
  final Week week;
  final String uid;
  const _WeekDetail({required this.poolId, required this.week, required this.uid});

  @override
  State<_WeekDetail> createState() => _WeekDetailState();
}

class _WeekDetailState extends State<_WeekDetail> {
  late final Future<(List<Game>, WeekPicks)> _future;

  @override
  void initState() {
    super.initState();
    final pools = context.read<PoolService>();
    final picks = context.read<PicksService>();
    _future = () async {
      final games = await pools.fetchGames(widget.poolId, widget.week.id);
      final mine = await picks.fetchPicks(widget.poolId, widget.week.id, widget.uid);
      return (games, mine);
    }();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<Game>, WeekPicks)>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText('Could not load picks:\n${snap.error}',
                style: const TextStyle(color: Colors.red)),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final (games, picks) = snap.data!;
        final last = games.where((g) => g.isLastGameOfWeek).firstOrNull;
        final homeScore = last?.homeScore;
        final awayScore = last?.awayScore;
        final actualTotal = (homeScore != null && awayScore != null) ? homeScore + awayScore : null;

        return Column(
          children: [
            for (final g in games) _gameRow(g, picks.selections[g.id]),
            if (picks.tiebreakerGuess != null)
              ListTile(
                dense: true,
                leading: const Icon(Icons.flag_outlined),
                title: Text('Tiebreaker guess: ${picks.tiebreakerGuess}'),
                subtitle: actualTotal != null
                    ? Text('Actual total: $actualTotal · off by ${(picks.tiebreakerGuess! - actualTotal).abs()}')
                    : null,
              ),
          ],
        );
      },
    );
  }

  Widget _gameRow(Game g, PickSide? pick) {
    final pickedName = pick == null ? null : (pick == PickSide.home ? g.homeTeam : g.awayTeam);
    final Widget icon;
    if (pick == null) {
      icon = const Icon(Icons.remove, color: Colors.grey);
    } else if (!g.isFinal) {
      icon = const Icon(Icons.hourglass_empty, color: Colors.grey);
    } else if (g.winner == pick) {
      icon = const Icon(Icons.check_circle, color: Colors.green);
    } else {
      icon = const Icon(Icons.cancel, color: Colors.red);
    }

    final result = g.isFinal ? ' · Final ${g.awayScore}-${g.homeScore}' : '';
    return ListTile(
      dense: true,
      leading: icon,
      title: Text('${g.awayTeam} @ ${g.homeTeam}'),
      subtitle: Text('${pickedName == null ? 'No pick' : 'Picked $pickedName'}$result'),
    );
  }
}