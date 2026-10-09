import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game.dart';
import '../models/pick.dart';
import '../models/pool.dart';
import '../models/week.dart';
import '../services/auth_service.dart';
import '../services/picks_service.dart';
import '../services/pool_service.dart';

/// One week's picks for everyone, side by side: a row per player, a column per game.
/// Other players' picks are hidden by the security rules until the week locks.
class WeekGridScreen extends StatelessWidget {
  final String poolId;
  final String weekId;
  const WeekGridScreen({super.key, required this.poolId, required this.weekId});

  @override
  Widget build(BuildContext context) {
    final pools = context.read<PoolService>();
    return StreamBuilder<Week>(
      stream: pools.watchWeek(poolId, weekId),
      builder: (context, weekSnap) {
        final week = weekSnap.data;
        return Scaffold(
          appBar: AppBar(title: Text(week == null ? "Everyone's picks" : "${week.title} · everyone's picks")),
          body: Builder(builder: (context) {
            if (weekSnap.hasError) return _error('Could not load the week:\n${weekSnap.error}');
            if (week == null) return const Center(child: CircularProgressIndicator());
            if (week.isOpen) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "Everyone's picks are hidden until picks lock, so nobody can copy anyone else.",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return _Grid(poolId: poolId, weekId: weekId);
          }),
        );
      },
    );
  }
}

Widget _error(String msg) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SelectableText(msg, style: const TextStyle(color: Colors.red)),
      ),
    );

class _Grid extends StatelessWidget {
  final String poolId;
  final String weekId;
  const _Grid({required this.poolId, required this.weekId});

  @override
  Widget build(BuildContext context) {
    final pools = context.read<PoolService>();
    final picks = context.read<PicksService>();
    final auth = context.read<AuthService>();
    final me = auth.currentUser?.uid;

    return StreamBuilder<Pool>(
      stream: pools.watchPool(poolId),
      builder: (context, poolSnap) {
        if (poolSnap.hasError) return _error('Could not load the pool:\n${poolSnap.error}');
        if (!poolSnap.hasData) return const Center(child: CircularProgressIndicator());
        final pool = poolSnap.data!;
        return StreamBuilder<List<Game>>(
          stream: pools.watchGames(poolId, weekId),
          builder: (context, gameSnap) {
            if (gameSnap.hasError) return _error('Could not load games:\n${gameSnap.error}');
            if (!gameSnap.hasData) return const Center(child: CircularProgressIndicator());
            final games = gameSnap.data!;
            return StreamBuilder<List<WeekPicks>>(
              stream: picks.watchAllPicks(poolId, weekId),
              builder: (context, pickSnap) {
                if (pickSnap.hasError) return _error('Could not load picks:\n${pickSnap.error}');
                if (!pickSnap.hasData) return const Center(child: CircularProgressIndicator());
                final byUid = {for (final p in pickSnap.data!) p.uid: p};
                return FutureBuilder<Map<String, String>>(
                  future: auth.displayNames(pool.memberUids),
                  builder: (context, nameSnap) {
                    final names = nameSnap.data ?? const <String, String>{};
                    return _table(context, pool, games, byUid, names, me);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  int _correct(List<Game> games, WeekPicks? p) {
    if (p == null) return 0;
    var n = 0;
    for (final g in games) {
      if (g.isFinal && g.winner != null && p.selections[g.id] == g.winner) n++;
    }
    return n;
  }

  Widget _table(BuildContext context, Pool pool, List<Game> games, Map<String, WeekPicks> byUid,
      Map<String, String> names, String? me) {
    final last = games.where((g) => g.isLastGameOfWeek).firstOrNull;
    final actualTotal = (last != null && last.homeScore != null && last.awayScore != null)
        ? last.homeScore! + last.awayScore!
        : null;

    final uids = [...pool.memberUids]..sort((a, b) {
        final c = _correct(games, byUid[b]).compareTo(_correct(games, byUid[a]));
        if (c != 0) return c;
        return (names[a] ?? '').toLowerCase().compareTo((names[b] ?? '').toLowerCase());
      });

    final headStyle = Theme.of(context).textTheme.labelSmall;

    DataColumn col(String top, [String? sub]) => DataColumn(
          label: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(top, style: headStyle?.copyWith(fontWeight: FontWeight.bold)),
              if (sub != null) Text(sub, style: headStyle),
            ],
          ),
        );

    final columns = <DataColumn>[
      const DataColumn(label: Text('Player')),
      const DataColumn(label: Text('Correct'), numeric: true),
      for (final g in games)
        col('${g.awayTeam} @', g.isFinal ? '${g.homeTeam} (${g.awayScore}-${g.homeScore})' : g.homeTeam),
      col('Tiebreaker', actualTotal != null ? 'actual $actualTotal' : 'total pts'),
    ];

    final rows = <DataRow>[];
    for (final uid in uids) {
      final p = byUid[uid];
      final submitted = p != null && p.selections.isNotEmpty;
      rows.add(DataRow(
        color: uid == me
            ? MaterialStatePropertyAll(Theme.of(context).colorScheme.primaryContainer)
            : null,
        cells: [
          DataCell(Text(names[uid] ?? '…',
              style: TextStyle(fontWeight: uid == me ? FontWeight.bold : FontWeight.normal))),
          DataCell(Text('${_correct(games, p)}')),
          for (final g in games) DataCell(_pickCell(g, submitted ? p.selections[g.id] : null)),
          DataCell(Text(
            p?.tiebreakerGuess == null
                ? '–'
                : actualTotal == null
                    ? '${p!.tiebreakerGuess}'
                    : '${p!.tiebreakerGuess} (off ${(p.tiebreakerGuess! - actualTotal).abs()})',
          )),
        ],
      ));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            'Ranked by correct picks so far. Green = correct, red = wrong, grey = game not final.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                headingRowHeight: 56,
                dataRowHeight: 44,
                columns: columns,
                rows: rows,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pickCell(Game g, PickSide? pick) {
    if (pick == null) return const Text('–', style: TextStyle(color: Colors.grey));
    final name = pick == PickSide.home ? g.homeTeam : g.awayTeam;
    Color? color;
    if (g.isFinal && g.winner != null) {
      color = g.winner == pick ? Colors.green.shade700 : Colors.red.shade700;
    }
    return Text(
      name,
      style: TextStyle(
        color: color ?? Colors.grey.shade600,
        fontWeight: color != null ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}