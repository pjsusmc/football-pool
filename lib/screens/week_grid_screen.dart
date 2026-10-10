import 'dart:ui' show PointerDeviceKind;
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
            return _Loader(poolId: poolId, weekId: weekId);
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

/// Loads the pool, games and picks, then hands them to the grid.
class _Loader extends StatelessWidget {
  final String poolId;
  final String weekId;
  const _Loader({required this.poolId, required this.weekId});

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
                    return _PicksGrid(
                      memberUids: pool.memberUids,
                      games: games,
                      picks: byUid,
                      names: nameSnap.data ?? const <String, String>{},
                      me: me,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// The grid itself. The player column stays put while the game columns scroll sideways, the
/// header row stays put while rows scroll up and down, and both scroll bars are always visible.
class _PicksGrid extends StatefulWidget {
  final List<String> memberUids;
  final List<Game> games;
  final Map<String, WeekPicks> picks;
  final Map<String, String> names;
  final String? me;
  const _PicksGrid({
    required this.memberUids,
    required this.games,
    required this.picks,
    required this.names,
    required this.me,
  });

  @override
  State<_PicksGrid> createState() => _PicksGridState();
}

class _PicksGridState extends State<_PicksGrid> {
  static const double _nameW = 130;
  static const double _correctW = 64;
  static const double _gameW = 120;
  static const double _tieW = 130;
  static const double _headH = 60;
  static const double _rowH = 48;

  final _leftV = ScrollController(); // player column
  final _rightV = ScrollController(); // game columns (drives the vertical scroll bar)
  final _horizontal = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _leftV.addListener(() => _sync(_leftV, _rightV));
    _rightV.addListener(() => _sync(_rightV, _leftV));
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !from.hasClients || !to.hasClients) return;
    final target = from.offset.clamp(0.0, to.position.maxScrollExtent).toDouble();
    if ((to.offset - target).abs() < 0.5) return;
    _syncing = true;
    to.jumpTo(target);
    _syncing = false;
  }

  @override
  void dispose() {
    _leftV.dispose();
    _rightV.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  int _correct(WeekPicks? p) {
    if (p == null) return 0;
    var n = 0;
    for (final g in widget.games) {
      if (g.isFinal && g.winner != null && p.selections[g.id] == g.winner) n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final games = widget.games;
    final last = games.where((g) => g.isLastGameOfWeek).firstOrNull;
    final actualTotal = (last != null && last.homeScore != null && last.awayScore != null)
        ? last.homeScore! + last.awayScore!
        : null;

    final uids = [...widget.memberUids]..sort((a, b) {
        final c = _correct(widget.picks[b]).compareTo(_correct(widget.picks[a]));
        if (c != 0) return c;
        return (widget.names[a] ?? '').toLowerCase().compareTo((widget.names[b] ?? '').toLowerCase());
      });

    final rightW = games.length * _gameW + _tieW;
    final border = BorderSide(color: theme.dividerColor);
    final headBg = theme.colorScheme.secondaryContainer;

    Widget cell(double w, double h, Widget child,
            {Color? bg, Alignment align = Alignment.centerLeft, bool bottom = true}) =>
        Container(
          width: w,
          height: h,
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: bg,
            border: Border(bottom: bottom ? border : BorderSide.none),
          ),
          child: child,
        );

    Widget head(double w, String top, [String? sub]) => cell(
          w,
          _headH,
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(top,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
              if (sub != null)
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall),
            ],
          ),
          bg: headBg,
        );

    Color? rowBg(String uid) => uid == widget.me ? theme.colorScheme.primaryContainer : null;

    final leftRows = ListView.builder(
      controller: _leftV,
      itemCount: uids.length,
      itemExtent: _rowH,
      itemBuilder: (_, i) {
        final uid = uids[i];
        return Row(children: [
          cell(
            _nameW,
            _rowH,
            Text(widget.names[uid] ?? '…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: uid == widget.me ? FontWeight.bold : FontWeight.normal)),
            bg: rowBg(uid),
          ),
          cell(_correctW, _rowH, Text('${_correct(widget.picks[uid])}'),
              bg: rowBg(uid), align: Alignment.center),
        ]);
      },
    );

    final rightRows = ListView.builder(
      controller: _rightV,
      itemCount: uids.length,
      itemExtent: _rowH,
      itemBuilder: (_, i) {
        final uid = uids[i];
        final p = widget.picks[uid];
        final submitted = p != null && p.selections.isNotEmpty;
        final guess = p?.tiebreakerGuess;
        return Row(children: [
          for (final g in games)
            cell(_gameW, _rowH, _pickText(g, submitted ? p.selections[g.id] : null), bg: rowBg(uid)),
          cell(
            _tieW,
            _rowH,
            Text(guess == null
                ? '–'
                : actualTotal == null
                    ? '$guess'
                    : '$guess (off ${(guess - actualTotal).abs()})'),
            bg: rowBg(uid),
          ),
        ]);
      },
    );

    // Mouse drag should scroll too, not only the wheel and scroll bars.
    final behavior = ScrollConfiguration.of(context).copyWith(
      scrollbars: false,
      dragDevices: PointerDeviceKind.values.toSet(),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Ranked by correct picks so far. Green = correct, red = wrong, grey = game not final. '
              'Scroll sideways to see every game.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: ScrollConfiguration(
            behavior: behavior,
            // Vertical bar for the whole grid, driven by the game columns' vertical list.
            child: Scrollbar(
              controller: _rightV,
              thumbVisibility: true,
              notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
              child: Row(
                children: [
                  SizedBox(
                    width: _nameW + _correctW,
                    child: Column(children: [
                      Row(children: [
                        head(_nameW, 'Player'),
                        head(_correctW, 'Correct'),
                      ]),
                      Expanded(child: leftRows),
                    ]),
                  ),
                  VerticalDivider(width: 1, color: theme.dividerColor),
                  Expanded(
                    // Horizontal bar sits at the bottom of the visible area, not the bottom of the data.
                    child: Scrollbar(
                      controller: _horizontal,
                      thumbVisibility: true,
                      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: rightW,
                          child: Column(children: [
                            Row(children: [
                              for (final g in games)
                                head(_gameW, '${g.awayTeam} @ ${g.homeTeam}',
                                    g.isFinal ? 'Final ${g.awayScore}-${g.homeScore}' : null),
                              head(_tieW, 'Tiebreaker', actualTotal != null ? 'Actual total $actualTotal' : 'Total points'),
                            ]),
                            Expanded(child: rightRows),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pickText(Game g, PickSide? pick) {
    if (pick == null) return const Text('–', style: TextStyle(color: Colors.grey));
    final name = pick == PickSide.home ? g.homeTeam : g.awayTeam;
    Color? color;
    if (g.isFinal && g.winner != null) {
      color = g.winner == pick ? Colors.green.shade700 : Colors.red.shade700;
    }
    return Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? Colors.grey.shade600,
        fontWeight: color != null ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}