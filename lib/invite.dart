import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/pool.dart';

/// Where your friends open the app. Change this if you ever move the site.
const appUrl = 'https://football-pool-7a153.web.app';

Future<void> _copy(BuildContext context, String text, String confirmation) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(confirmation)));
  } catch (_) {
    // Some browsers block clipboard access; show the text so it can be copied by hand.
    messenger.showSnackBar(
      SnackBar(content: SelectableText('Could not copy automatically. Pool ID: ${text.split('\n').last}')),
    );
  }
}

/// Copies just the pool ID.
Future<void> copyPoolId(BuildContext context, Pool pool) =>
    _copy(context, pool.id, 'Pool ID copied');

/// Copies a ready-to-send message with the link, the steps and the pool ID.
Future<void> copyInvite(BuildContext context, Pool pool) => _copy(
      context,
      'Join my football pool "${pool.name}"!\n'
      '1. Open $appUrl and create an account\n'
      '2. Tap Join and enter this pool ID:\n'
      '${pool.id}',
      'Invite copied. Paste it into a text or email.',
    );