import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../main.dart';
import '../md_toc.dart';
import '../md_toc_view.dart';
import '../md_zoom.dart';
import '../models.dart';
import '../yt_links.dart';
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
  bool _chapterizing = false;
  bool _loadingFull = false;
  String _summaryStatus = '';
  String? _chapterSetTab; // 'ai' | 'original' | null (auto)

  // Saved results for THIS video (the global Results section, scoped).
  List<SavedResult> _results = [];
  bool _resultsLoading = false;
  String? _resultsError;

  @override
  void initState() {
    super.initState();
    Future.microtask(_ensureFull);
    Future.microtask(_loadResults);
  }

  Future<void> _ensureFull() async {
    final state = context.read<AppState>();
    final v = _video(state);
    if (v == null || v.fullLoaded) return;
    setState(() => _loadingFull = true);
    try {
      await state.ensureFullVideo(v);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not load full video: $e');
    }
    if (mounted) setState(() => _loadingFull = false);
  }

  String get _activeChapterTab {
    if (_chapterSetTab == 'ai') return 'ai';
    if (_chapterSetTab == 'original') return 'original';
    final v = _video(context.read<AppState>());
    if (v == null) return 'original';
    if (v.chapterSet == 'ai') return 'ai';
    if (v.chapterSet == 'original') return 'original';
    if (v.aiChapters != null && v.aiChapters!.isNotEmpty) return 'ai';
    if (v.originalChapters != null && v.originalChapters!.isNotEmpty) return 'original';
    if (v.chapters.any((c) => c is Map && c['generated'] == true)) return 'ai';
    return 'original';
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
      // The built-in prompt list defines the order of this tab.
      if (state.defaultPrompts.isEmpty) {
        try {
          await state.refreshPrompts();
        } catch (_) {}
      }
      final rs = await state.api.listResults(videoId: widget.videoId);
      if (mounted) {
        setState(() => _results = sortByPromptOrder(rs, state.defaultPrompts));
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
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _sending = true;
      v.chat.add(ChatMessage(role: 'user', content: q, at: now));
      _chatController.clear();
    });
    try {
      final resp = await state.askVideo(v, v.chat);
      v.chat.add(ChatMessage(
        role: 'assistant',
        content: resp.content,
        model: resp.model,
        cost: resp.cost,
        at: DateTime.now().millisecondsSinceEpoch,
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
      length: 5,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(v.title ?? v.videoId,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Chapters'),
            Tab(text: 'Results'),
            Tab(text: 'Audio'),
            Tab(text: 'Transcript'),
            Tab(text: 'Chat'),
          ]),
          actions: [
            if (yt != null)
              IconButton(
                tooltip: 'Watch on YouTube',
                icon: const Icon(Icons.smart_display_outlined),
                onPressed: () => _openUrl(yt),
              ),
            if (hasYouTubeSource(v))
              IconButton(
                tooltip: 'Download in the YouTube app',
                icon: const Icon(Icons.download_for_offline_outlined),
                onPressed: () => openInYouTubeApp(context, v),
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
        body: Column(
          children: [
            if (_loadingFull) const LinearProgressIndicator(),
            Expanded(
              child: TabBarView(
                children: [
                  _buildChapters(state, v),
                  // Past prompt results for THIS video — the global Results
                  // section, scoped, between Chapters and Audio.
                  PastResultsTab(
                    results: _results,
                    loading: _resultsLoading,
                    error: _resultsError,
                    onRefresh: _loadResults,
                    videoId: v.videoId,
                    sourceTitle: v.title ?? v.videoId,
                    sourceAuthor: v.author,
                  ),
                  _buildAudioTab(state, v),
                  _buildTranscript(v),
                  _buildChat(state, v),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rechapterize(AppState state, Video v) async {
    setState(() => _chapterizing = true);
    try {
      final chs = await state.aiChapterizeVideo(v);
      if (mounted) {
        setState(() => _chapterSetTab = 'ai');
        showSnack(context, 'Generated ${chs.length} AI chapters.');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Chapterize failed: $e');
    }
    if (mounted) setState(() => _chapterizing = false);
  }

  Future<void> _summarizeChapters(
      AppState state, Video v, List<dynamic> targetChapters) async {
    setState(() {
      _summarizing = true;
      _summaryStatus = 'Summarizing…';
    });
    try {
      final n = await state.summarizeChapters(v,
          targetChapters: targetChapters, onProgress: (s) {
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

  Future<void> _exportChapters(Video v, List<dynamic> chapters) async {
    final isOrig = _activeChapterTab == 'original';
    final kind = isOrig ? 'Original Chapters' : 'AI Generated Chapters';
    final name = downloadName(
      title: v.title ?? v.videoId,
      kind: kind,
      date: v.savedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(v.savedAt!)
          : null,
      ext: 'md',
    );
    final buf = StringBuffer('# ${v.title ?? v.videoId} — $kind\n\n');
    for (var i = 0; i < chapters.length; i++) {
      final c = Map<String, dynamic>.from(chapters[i] as Map);
      final title = c['title']?.toString() ?? 'Chapter ${i + 1}';
      final start = (c['start'] as num?)?.toInt();
      final timeLabel = start != null ? ' (${_fmtTime(start)})' : '';
      final entry = formatChapterMarkdown(c);
      buf.write(
          '## ${i + 1}. $title$timeLabel\n\n${entry.isNotEmpty ? entry : '_No AI summary yet._'}\n\n');
    }
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(utf8.encode(buf.toString().trim())),
          mimeType: 'text/markdown',
          name: name,
        ),
      ],
      subject: '${v.title ?? v.videoId} — $kind',
      sharePositionOrigin: origin,
    ));
  }

  Widget _buildChapters(AppState state, Video v) {
    final activeTab = _activeChapterTab;
    final displayChapters = v.activeChapterList(activeTab);
    final hasBothSets = v.hasBothChapterSets;
    final isOrig = activeTab == 'original';

    if (displayChapters.isEmpty && !v.hasAiChapters && !v.hasOriginalChapters) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No chapters for this video yet.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: _chapterizing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                label: Text(_chapterizing ? 'Chapterizing…' : 'Generate AI Chapters'),
                onPressed: _chapterizing ? null : () => _rechapterize(state, v),
              ),
            ],
          ),
        ),
      );
    }

    final yt = ytUrl(v);
    final hasSummaries = displayChapters
        .any((c) => ((c as Map)['summary'] ?? '').toString().isNotEmpty);

    return Column(
      children: [
        if (hasBothSets)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Row(
              children: [
                ChoiceChip(
                  avatar: const Text('🤖'),
                  label: Text('AI Generated (${v.aiChapters!.length})'),
                  selected: !isOrig,
                  onSelected: (_) {
                    setState(() => _chapterSetTab = 'ai');
                    state.switchVideoChapterSet(v, 'ai');
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  avatar: const Text('📋'),
                  label: Text('Original (${v.originalChapters!.length})'),
                  selected: isOrig,
                  onSelected: (_) {
                    setState(() => _chapterSetTab = 'original');
                    state.switchVideoChapterSet(v, 'original');
                  },
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _chapterizing
                      ? 'Chapterizing…'
                      : _summarizing
                          ? _summaryStatus
                          : isOrig
                              ? 'Original Chapters (${displayChapters.length})'
                              : 'AI Generated Chapters (${displayChapters.length})',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              FilledButton.tonalIcon(
                icon: _chapterizing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(
                  _chapterizing
                      ? 'Working…'
                      : v.hasAiChapters
                          ? 'Re-chapterize'
                          : 'AI Chapterize',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: (_chapterizing || _summarizing)
                    ? null
                    : () => _rechapterize(state, v),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                icon: _summarizing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.summarize_outlined, size: 16),
                label: Text(
                  hasSummaries ? 'Re-summarize' : 'Summarize',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: (_summarizing || _chapterizing || displayChapters.isEmpty)
                    ? null
                    : () => _summarizeChapters(state, v, displayChapters),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Export Chapters .md',
                icon: const Icon(Icons.download_outlined, size: 20),
                onPressed: displayChapters.isEmpty
                    ? null
                    : () => _exportChapters(v, displayChapters),
              ),
            ],
          ),
        ),
        if (_summarizing || _chapterizing) const LinearProgressIndicator(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: displayChapters.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = Map<String, dynamic>.from(displayChapters[i] as Map);
              final title = c['title']?.toString() ?? 'Chapter ${i + 1}';
              final summary = c['summary']?.toString() ?? '';
              final start = (c['start'] as num?)?.toInt();
              final chapterUrl =
                  (yt != null && start != null) ? ytUrlAt(yt, start) : null;
              final entry = formatChapterMarkdown(c);
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
                      body: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ZoomMd(
                          data: [
                            if (chapterUrl != null)
                              '▶ [Watch from ${_fmtTime(start!)}]($chapterUrl)\n',
                            if (entry.isNotEmpty) '### Chapter Guide\n\n$entry\n\n---\n',
                            v.chapterText(i, chapterList: displayChapters),
                          ].join('\n'),
                          scrollable: true,
                        ),
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

  Future<void> _exportChat(Video v) async {
    if (v.chat.isEmpty) return;
    final name = downloadName(
      title: v.title ?? 'Video',
      kind: 'Q and A',
      date: v.savedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(v.savedAt!)
          : null,
      ext: 'md',
    );
    final buf = StringBuffer('# ${v.title ?? 'Video'} — Q&A Transcript\n\n');
    for (final m in v.chat) {
      final timeTag = m.at != null
          ? ' _(${DateTime.fromMillisecondsSinceEpoch(m.at!).toLocal().toString().split('.').first})_'
          : '';
      if (m.role == 'user') {
        buf.write('## Q: ${m.content}$timeTag\n\n');
      } else {
        final meta = m.model != null
            ? '\n\n> *Answered via ${m.model}${m.cost != null ? ' (${m.cost})' : ''}$timeTag*'
            : '';
        buf.write('${m.content}$meta\n\n');
      }
    }
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(utf8.encode(buf.toString().trim())),
          mimeType: 'text/markdown',
          name: name,
        ),
      ],
      subject: '${v.title ?? 'Video'} — Q&A',
      sharePositionOrigin: origin,
    ));
  }

  Widget _buildChat(AppState state, Video v) {
    return Column(
      children: [
        if (v.chat.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${v.chat.where((m) => m.role == 'user').length} question(s) in transcript',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Export Q&A .md', style: TextStyle(fontSize: 12)),
                  onPressed: () => _exportChat(v),
                ),
              ],
            ),
          ),
        Expanded(
          child: v.chat.isEmpty
              ? const Center(child: Text('Ask anything about this video.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: v.chat.length,
                  itemBuilder: (context, i) {
                    final m = v.chat[i];
                    final isUser = m.role == 'user';
                    final meta = [
                      if (m.at != null)
                        DateTime.fromMillisecondsSinceEpoch(m.at!)
                            .toLocal()
                            .toString()
                            .substring(5, 16),
                      if (m.model != null && m.model!.isNotEmpty) m.model!,
                      if (m.cost != null && m.cost!.isNotEmpty) m.cost!,
                    ].join(' · ');

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
                        child: Column(
                          crossAxisAlignment: isUser
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (meta.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  meta,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline,
                                  ),
                                ),
                              ),
                            isUser
                                ? SelectableText(m.content)
                                : ZoomMd(data: m.content),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: isUser
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () {
                                    Clipboard.setData(
                                        ClipboardData(text: m.content));
                                    showSnack(context, 'Copied to clipboard.');
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.copy,
                                            size: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline),
                                        const SizedBox(width: 2),
                                        Text('Copy',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
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
          if (!v.isSupportedLanguage)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This video transcript is in an unsupported language (${v.language}). '
                      "Phil's Library only supports English ('en') and Spanish ('es') transcripts.",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text('${v.wordCount} words')),
              if (v.language != null)
                Chip(
                  label: Text(v.language!),
                  avatar: !v.isSupportedLanguage
                      ? const Icon(Icons.warning_amber_rounded, size: 16)
                      : null,
                ),
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

  Widget _buildAudioTab(AppState state, Video v) {
    final audioResults = _results.where((r) => r.hasAudio).toList();
    if (audioResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.audiotrack_outlined,
                  size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              const Text(
                'No audio narrations for this video yet.\n'
                'Audio generated from prompt results will appear here for offline download and listening.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh audio'),
                onPressed: _loadResults,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: audioResults.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = audioResults[i];
        final name = r.promptName ?? 'Narration';
        final meta = [
          fmtWhen(r.createdAt),
          if (r.model != null && r.model!.isNotEmpty) r.model!,
          if (r.cost != null && r.cost!.isNotEmpty) r.cost!,
        ].join(' · ');

        return Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(Icons.audiotrack,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          if (meta.isNotEmpty)
                            Text(meta,
                                style:
                                    Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.article_outlined, size: 18),
                      label: const Text('View text'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SavedResultPage(
                            result: r,
                            sourceTitle: v.title ?? v.videoId,
                            sourceLine:
                                '${v.title ?? v.videoId}${v.author == null || v.author!.isEmpty ? '' : ' — ${v.author}'} (video)',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.download_for_offline_outlined,
                          size: 18),
                      label: const Text('Download .mp3'),
                      onPressed: () => _downloadAudio(r, v),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadAudio(SavedResult r, Video v) async {
    showSnack(context, 'Fetching audio…');
    try {
      final state = context.read<AppState>();
      final bytes = await state.api.fetchVideoResultAudioBytes(r.id);
      if (bytes == null || bytes.isEmpty) {
        if (mounted) showSnack(context, 'Audio data not found on server.');
        return;
      }
      final fileName = downloadName(
        title: v.title ?? v.videoId,
        kind: r.promptName ?? 'Narration',
        date: DateTime.tryParse(r.createdAt ?? ''),
        ext: 'mp3',
      );
      final box = mounted ? context.findRenderObject() as RenderBox? : null;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'audio/mpeg', name: fileName)],
        subject: '${v.title ?? v.videoId} — ${r.promptName ?? 'Audio'}',
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      if (mounted) showSnack(context, 'Failed to download audio: $e');
    }
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
