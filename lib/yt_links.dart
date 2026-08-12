// Handing a library video over to the official YouTube Android app.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';

/// The 11-char YouTube id for [v] — from the saved `videoId`, else parsed out
/// of the saved URL. Null for pasted transcripts with no YouTube source.
String? youtubeVideoId(Video v) {
  final id = v.videoId.trim();
  if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) return id;
  final m = RegExp(r'(?:v=|youtu\.be/|/shorts/|/embed/|/live/)([a-zA-Z0-9_-]{11})')
      .firstMatch((v.url ?? '').trim());
  return m?.group(1);
}

/// True when [v] can be handed to YouTube at all — use it to hide the button.
bool hasYouTubeSource(Video v) => youtubeVideoId(v) != null;

/// Open [v] in the official YouTube **Android app**, where its own Download
/// button (Premium offline) is one tap away.
///
/// Android exposes no public intent that *starts* a YouTube download — the app
/// registers only the `vnd.youtube:` view deep link — so handing the video over
/// is the most a third-party app can do. The explicit scheme is what keeps this
/// out of the browser; the https URL is only a fallback for when the app isn't
/// installed. Note we never call `canLaunchUrl` here: package-visibility rules
/// on Android 11+ would make it answer false without a `<queries>` entry, and
/// this repo generates `android/` with `flutter create`, so there is no
/// checked-in manifest to add one to. `launchUrl` itself is unaffected.
Future<void> openInYouTubeApp(BuildContext context, Video v) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String m) => messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(m)));

  final id = youtubeVideoId(v);
  final web = id != null
      ? 'https://www.youtube.com/watch?v=$id'
      : (v.url ?? '').trim();
  if (web.isEmpty) {
    snack('No YouTube source saved for this transcript.');
    return;
  }

  for (final uri in [
    if (id != null) Uri.parse('vnd.youtube:$id'),
    Uri.parse(web),
  ]) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // ActivityNotFoundException when the YouTube app isn't installed —
      // fall through to the next candidate rather than surfacing it.
    }
  }
  snack('Could not open YouTube.');
}
