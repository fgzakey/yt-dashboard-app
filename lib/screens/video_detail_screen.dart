import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../main.dart';
import '../md_zoom.dart';
import '../models.dart';
import '../md_toc_view.dart';
import 'past_results.dart';

class VideoDetailScreen extends StatefulWidget {
  final String videoId;
  const VideoDetailScreen({super.key, required this.videoId});

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen> {
  final _chatController = TextEditingController();
  bool _sending = false;
  bool _running = false;
  bool _summarizing = false;
  String _summaryStatus = '';

  // Saved results for THIS video (the global Results section, scoped).
  List<SavedResult> _results = [];
  bool _resultsLoading = false;
  String? _resultsError;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadResults);
  }

  Video? _video(AppState state) {
    try {
      return state.videos.firstWhere((v) => v.videoId == widget.videoId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadResults() async {
    if (!mounted) return;
    setState(() {
      _resultsLoading = true;
      _resultsError = null;
    });
    try {
      final state = context.read<AppState>();
      // The prompt list defines the order of this tab, so make sure it's loaded.
      if (state.prompts.isEmpty) {
        try {
          await state.refreshPrompts();
        } catch (_) {}
      }
      final rs = await state.api.listResults(videoId: widget.videoId);
      if (mounted) {
        setState(() => _results = sortByPromptOrder(rs, state.prompts));
      }
    } catch (e) {
      if (mounted) setState(() => _resultsError = e.toString());
    }
    if (mounted) setState(() => _resultsLoading = false);
  }

  // ---- YouTube deep links -------------------------------------------------

  /// Best watch URL for a saved video: prefer a real YouTube link, else
  /// rebuild one from an 11-char video id. Null for pasted transcripts.
  /// (Same rule as the web dashboard's `youtubeUrl`.)
  static String? ytUrl(Video v) {
    final u = (v.url ?? '').trim();
    if (RegExp(r'youtu\.?be').hasMatch(u)) return u;
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(v.videoId)) {
      return 'https://www.youtube.com/watch?v=${v.videoId}';
    }
    return null;
  }

  /// The same URL, seeked to [seconds].
  static String ytUrlAt(String base, int seconds) =>
      '$base${base.contains('?') ? '&' : '?'}t=${seconds}s';

  Future<void> _openUrl(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) showSnack(context, 'Could not open $url');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the link: $e');
    }
  }

  Future<void> _send(AppState state, Video v) async {
    final q = _chatController.text.trim();
    if (q.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      v.chat.add(ChatMessage(role: 'user', content: q));
      _chatController.clear();
    });
    try {
      final resp = await state.askVideo(v, v.chat);
      v.chat.add(ChatMessage(
        role: 'assistant',
        content: resp.content,
        model: resp.model,
        cost: resp.cost,
      ));
      await state.saveVideo(v); // persist chat to the shared DB
    } catch (e) {
      if (mounted) showSnack(context, 'Chat failed: $e');
      v.chat.removeLast(); // roll back the user message
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _runPrompt(AppState state, Video v) async {
    if (state.prompts.isEmpty) await state.refreshPrompts();
    if (!mounted) return;
    final prompt = await showModalBottomSheet<PromptTemplate>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Run a standardized prompt',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ...state.prompts.map((p) => ListTile(
                leading: Icon(p.builtin ? Icons.star_outline : Icons.edit_note),
                title: Text(p.name),
                subtitle: Text(p.description,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, p),
              )),
        ],
      ),
    );
    if (prompt == null || !mounted) return;

    setState(() => _running = true);
    try {
      final resp = await context.read<AppState>().runPrompt(v, prompt);
      if (!mounted) return;
      setState(() => _running = false);
      await showDialog(
        context: context,
        builder: (ctx) => Dialog.fullscreen(
          child: _ResultViewer(
            title: prompt.name,
            content: resp.content,
            onSave: () async {
              await state.api.saveResult(
                content: resp.content,
                videoId: v.videoId,
                videoTitle: v.title,
                promptName: prompt.name,
                model: resp.model,
                cost: resp.cost,
              );
              if (ctx.mounted) {
                Navigator.pop(ctx);
                showSnack(context, 'Saved to Results.');
              }
            },
          ),
        ),
      );
      await _loadResults(); // the new result shows up in the Chat tab panel
    } catch (e) {
      if (mounted) {
        setState(() => _running = false);
        showSnack(context, 'Prompt failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final v = _video(state);
    if (v == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Video not found.')),
      );
    }
    final yt = ytUrl(v);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(v.title ?? v.videoId,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Chat'),
            Tab(text: 'Chapters'),
            Tab(text: 'Results'),
            Tab(text: 'Transcript'),
          ]),
          actions: [
            if (yt != null)
              IconButton(
                tooltip: 'Watch on YouTube',
                icon: const Icon(Icons.smart_display_outlined),
                onPressed: () => _openUrl(yt),
              ),
            const TextSizeButtons(),
            IconButton(
              tooltip: 'Run prompt',
              icon: _running
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.bolt),
              onPressed: _running ? null : () => _runPrompt(state, v),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildChat(state, v),
            _buildChapters(state, v),
            // Past prompt results for THIS video — the global Results
            // section, scoped, between Chapters and Transcript.
            PastResultsTab(
              results: _results,
              loading: _resultsLoading,
              error: _resultsError,
              onRefresh: _loadResults,
            ),
            _buildTranscript(v),
          ],
        ),
      ),
    );
  }

  Future<void> _summarizeChapters(AppState state, Video v) async {
    setState(() {
      _summarizing = true;
      _summaryStatus = 'Summarizing…';
    });
    try {
      final n = await state.summarizeChapters(v, onProgress: (s) {
        if (mounted) setState(() => _summaryStatus = s);
      });
      if (mounted) showSnack(context, 'Summarized $n chapter(s).');
    } catch (e) {
      if (mounted) showSnack(context, 'Summarize failed: $e');
    }
    if (mounted) {
      setState(() {
        _summarizing = false;
        _summaryStatus = '';
      });
    }
  }

  Widget _buildChapters(AppState state, Video v) {
    if (v.chapters.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No chapters for this video.\nFetch chapters in the web dashboard (they sync here).',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final yt = ytUrl(v);
    final hasSummaries = v.chapters
        .any((c) => ((c as Map)['summary'] ?? '').toString().isNotEmpty);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _summarizing
                      ? _summaryStatus
                      : yt == null
                          ? '${v.chapters.length} chapters — tap one to read'
                          : '${v.chapters.length} chapters — tap to read, ▶ to watch',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilledButton.tonalIcon(
                icon: _summarizing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(hasSummaries ? 'Re-summarize' : 'Summarize'),
                onPressed:
                    _summarizing ? null : () => _summarizeChapters(state, v),
              ),
            ],
          ),
        ),
        if (_summarizing) const LinearProgressIndicator(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: v.chapters.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = Map<String, dynamic>.from(v.chapters[i] as Map);
              final title = c['title']?.toString() ?? 'Chapter ${i + 1}';
              final summary = c['summary']?.toString() ?? '';
              final start = (c['start'] as num?)?.toInt();
              final chapterUrl =
                  (yt != null && start != null) ? ytUrlAt(yt, start) : null;
              return ListTile(
                leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                title: Text(title),
                subtitle: Text(
                  [
                    if (start != null) _fmtTime(start),
                    if (summary.isNotEmpty) summary,
                  ].join(' — '),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                // Live link: opens the video in the YouTube app at this chapter.
                trailing: chapterUrl == null
                    ? null
                    : IconButton(
                        tooltip: 'Watch from ${_fmtTime(start!)}',
                        icon: const Icon(Icons.play_circle_outline),
                        onPressed: () => _openUrl(chapterUrl),
                      ),
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => Dialog.fullscreen(
                    child: Scaffold(
                      appBar: AppBar(
                        title: Text(title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        leading: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                        actions: [
                          if (chapterUrl != null)
                            IconButton(
                              tooltip: 'Watch from ${_fmtTime(start!)}',
                              icon: const Icon(Icons.play_circle_outline),
                              onPressed: () => _openUrl(chapterUrl),
                            ),
                          const TextSizeButtons(),
                          const SizedBox(width: 4),
                        ],
                      ),
                      body: ZoomMd(
                        data: [
                          if (chapterUrl != null)
                            '▶ [Watch from ${_fmtTime(start!)}]($chapterUrl)\n',
                          if (summary.isNotEmpty) '**Summary:** $summary\n',
                          v.chapterText(i),
                        ].join('\n'),
                        scrollable: true,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _fmtTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }

  Widget _buildChat(AppState state, Video v) {
    return Column(
      children: [
        Expanded(
          child: v.chat.isEmpty
              ? const Center(child: Text('Ask anything about this video.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: v.chat.length,
                  itemBuilder: (context, i) {
                    final m = v.chat[i];
                    final isUser = m.role == 'user';
                    return Align(
                      alignment:
                          isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.85),
                        decoration: BoxDecoration(
                          color: isUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: isUser
                            ? Text(m.content)
                            : ZoomMd(data: m.content),
                      ),
                    );
                  },
                ),
        ),
        if (_sending) const LinearProgressIndicator(),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Ask about the video…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(state, v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: _sending ? null : () => _send(state, v),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTranscript(Video v) {
    final yt = ytUrl(v);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text('${v.wordCount} words')),
              if (v.language != null) Chip(label: Text(v.language!)),
              if (yt != null)
                ActionChip(
                  avatar: const Icon(Icons.smart_display_outlined, size: 16),
                  label: const Text('Watch on YouTube'),
                  onPressed: () => _openUrl(yt),
                ),
              ActionChip(
                avatar: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: v.text));
                  showSnack(context, 'Transcript copied.');
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(v.text),
        ],
      ),
    );
  }
}

class _ResultViewer extends StatelessWidget {
  final String title;
  final String content;
  final Future<void> Function() onSave;

  const _ResultViewer(
      {required this.title, required this.content, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          const TextSizeButtons(),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              showSnack(context, 'Copied.');
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
            onPressed: onSave,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: MdWithToc(data: content),
    );
  }
}
