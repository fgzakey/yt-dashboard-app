import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../main.dart';
import 'video_detail_screen.dart';

class VideosScreen extends StatelessWidget {
  const VideosScreen({super.key});

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Videos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: state.loadingVideos ? null : () => state.refreshVideos(),
          ),
        ],
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
        if (state.videos.isEmpty) {
          return const Center(
            child: Text('No videos yet.\nTap "Add video" to fetch a transcript.',
                textAlign: TextAlign.center),
          );
        }
        return RefreshIndicator(
          onRefresh: () => state.refreshVideos(),
          child: ListView.separated(
            itemCount: state.videos.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final v = state.videos[i];
              return ListTile(
                leading: const Icon(Icons.smart_display_outlined),
                title: Text(v.title ?? v.videoId,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    if (v.author != null && v.author!.isNotEmpty) v.author!,
                    '${v.wordCount} words',
                    if (v.chat.isNotEmpty) '${v.chat.length ~/ 2} Q&A',
                  ].join(' · '),
                ),
                trailing: IconButton(
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
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => VideoDetailScreen(videoId: v.videoId)),
                ),
              );
            },
          ),
        );
      }),
    );
  }
}
