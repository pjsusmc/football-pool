import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/game.dart';

class GamePickCard extends StatelessWidget {
  final Game game;
  final PickSide? selected;
  final bool enabled;
  final ValueChanged<PickSide> onSelect;

  const GamePickCard({
    super.key,
    required this.game,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final kickoff = DateFormat('EEE h:mm a').format(game.kickoffAt.toLocal());
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(kickoff, style: Theme.of(context).textTheme.labelMedium),
                if (game.isLastGameOfWeek)
                  const Chip(
                    label: Text('Tiebreaker game', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _teamButton(context, game.awayTeam, 'Away', PickSide.away)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('@', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Expanded(child: _teamButton(context, game.homeTeam, 'Home', PickSide.home)),
              ],
            ),
            if (game.isFinal)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Final: ${game.awayTeam} ${game.awayScore} - ${game.homeScore} ${game.homeTeam}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _teamButton(BuildContext context, String label, String sub, PickSide side) {
    return OutlinedButton(
      onPressed: enabled ? () => onSelect(side) : null,
      style: OutlinedButton.styleFrom(
        backgroundColor:
            selected == side ? Theme.of(context).colorScheme.primaryContainer : null,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Column(
        children: [
          Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(sub, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
