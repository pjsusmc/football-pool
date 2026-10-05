import 'dart:async';
import 'package:flutter/material.dart';

class CountdownBanner extends StatefulWidget {
  final DateTime lockAt;
  final bool isLocked;
  const CountdownBanner({super.key, required this.lockAt, required this.isLocked});

  @override
  State<CountdownBanner> createState() => _CountdownBannerState();
}

class _CountdownBannerState extends State<CountdownBanner> {
  late final Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _remaining = widget.lockAt.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _remaining = widget.lockAt.difference(DateTime.now()));
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    if (d.inHours >= 24) return '${d.inDays}d ${d.inHours.remainder(24)}h left to pick';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))} left to pick';
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.isLocked || _remaining.isNegative;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: locked ? Colors.grey.shade700 : Colors.green.shade700,
      child: Text(
        locked ? 'Picks are locked for this week' : _format(_remaining),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}
