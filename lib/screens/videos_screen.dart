import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../main.dart';
import '../models.dart';
import '../yt_links.dart';
import 'video_detail_screen.dart';

/// Short label for the value the list is CURRENTLY ordered by, so a row's
/// position is explainable at a glance. Empty for the default (last modified)
/// order — that is the long-standing behaviour and needs no annotation.
/// Mirrors `librarySortStamp` in phils-library/app/library-search.js.
String sortStamp(Video v, VideoSort sort) {
  if (sort == VideoSort.savedAt) return '';
  const verbs = {
    VideoSort.opened: 'opened',
    VideoSort.added: 'added',
    VideoSort.extracted: 'extracted',
  };
  // Not `verbs[sort]!`: unlike the switch expressions in app_state.dart, a map
  // lookup is not exhaustiveness-checked, so a fifth VideoSort would compile
  // here and then throw at render time. Degrade to no stamp instead.
  final verb = verbs[sort];
  if (verb == null) return '';
  final ms = sort.keyOf(v);
  if (ms == null) return 'never $verb';

  final then = DateTime.fromMillisecondsSinceEpoch(ms);
  final days = DateTime.now().difference(then).inDays;
  if (days <= 0) return '$verb today';
  if (days == 1) return '$verb yesterday';
  if (days < 30) return '$verb ${days}d ago';
  // Same "12 Mar 2026" shape as the web dashboard's librarySortStamp.
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '$verb ${then.day} ${months[then.month - 1]} ${then.year}';
}

class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  // Owned by the widget, not AppState: the controller is a UI object with a
  // lifecycle, while the query string it mirrors lives in AppState so the
  // filtered list and the count stay in one place.
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Seed from the surviving query. main.dart holds the tab screens in a const
    // list, so switching tabs DISPOSES this State while AppState.videoQuery
    // lives on in the provider — without this the box comes back empty over a
    // still-filtered list, which is exactly the "looks like data loss" failure
    // the not-persisting-the-query rule exists to prevent.
    _searchCtrl.text = context.read<AppState>().videoQuery;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _addVideo(BuildContext context) async {
    final state = context.read<AppState>();
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add video'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'YouTube URL or video ID',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Fetch transcript'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Fetching transcript…\nThis can take a minute.')),
          ],
        ),
      ),
    );
    try {
      final v = await state.addVideoFromUrl(url.trim());
      if (!context.mounted) return;
      Navigator.pop(context); // close progress dialog
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoDetailScreen(videoId: v.videoId)),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final shown = state.visibleVideos;
    final filtering = state.videoQuery.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        // The count makes a filtered list impossible to mistake for a library
        // that lost rows — "3 / 27" while filtering, "27" otherwise. Same rule
        // as the web dashboard's panel headers.
        title: Text(state.videos.isEmpty
            ? 'Videos'
            : filtering
                ? 'Videos (${shown.length} / ${state.videos.length})'
                : 'Videos (${state.videos.length})'),
        actions: [
          PopupMenuButton<VideoSort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Order by',
            initialValue: state.videoSort,
            // The discard is explicit: setVideoSort's SharedPreferences write is
            // a preference, not data, so a failure must not become an unhandled
            // async error over the list.
            onSelected: (s) {
              state.setVideoSort(s);
            },
            // Checked, not plain, items — initialValue only positions the menu,
            // it doesn't mark the active order the way the web <select> does.
            itemBuilder: (_) => [
              for (final s in VideoSort.values)
                CheckedPopupMenuItem(
                  value: s,
                  checked: s == state.videoSort,
                  child: Text(s.label),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: state.loadingVideos ? null : () => state.refreshVideos(),
          ),
        ],
        bottom: state.videos.isEmpty
            ? null
            : PreferredSize(
                // Not a fixed height: main.dart applies a user-settable global
                // TextScaler (mdScale, up to 3.0), so a hard 56 overflows the
                // field the moment the text size is turned up.
                preferredSize: Size.fromHeight(
                    MediaQuery.textScalerOf(context).scale(56).clamp(56.0, 120.0)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onChanged: state.setVideoQuery,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      hintText: 'Search title or channel…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: filtering
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchCtrl.clear();
                                state.setVideoQuery('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addVideo(context),
        icon: const Icon(Icons.add),
        label: const Text('Add video'),
      ),
      body: Builder(builder: (context) {
        if (state.loadingVideos && state.videos.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.videosError != null && state.videos.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load videos:\n${state.videosError}',
                  textAlign: TextAlign.center),
            ),
          );
        }
        // The "no videos yet" state keys off the UNFILTERED list, so it can
        // never fight the "no videos match" message below.
        if (state.videos.isEmpty) {
          return const Center(
            child: Text('No videos yet.\nTap "Add video" to fetch a transcript.',
                textAlign: TextAlign.center),
          );
        }
        if (shown.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No videos match “${state.videoQuery.trim()}”.',
                  textAlign: TextAlign.center),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => state.refreshVideos(),
          child: ListView.separated(
            itemCount: shown.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final v = shown[i];
              final stamp = sortStamp(v, state.videoSort);
              return ListTile(
                leading: const Icon(Icons.smart_display_outlined),
                title: Text(v.title ?? v.videoId,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    if (v.author != null && v.author!.isNotEmpty) v.author!,
                    '${v.wordCount} words',
                    if (v.chat.isNotEmpty) '${v.chat.length ~/ 2} Q&A',
                    if (stamp.isNotEmpty) stamp,
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasYouTubeSource(v))
                      IconButton(
                        tooltip: 'Download in the YouTube app',
                        icon: const Icon(Icons.download_for_offline_outlined),
                        onPressed: () => openInYouTubeApp(context, v),
                      ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete video?'),
                            content: Text(v.title ?? v.videoId),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (ok == true) await state.deleteVideo(v.videoId);
                      },
                    ),
                  ],
                ),
                onTap: () {
                  // Stamp "last accessed", then navigate — deliberately NOT
                  // awaited, so a slow or offline server never delays opening
                  // the video. touchVideo swallows its own errors.
                  state.touchVideo(v.videoId);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => VideoDetailScreen(videoId: v.videoId)),
                  );
                },
              );
            },
          ),
        );
      }),
    );
  }
}
