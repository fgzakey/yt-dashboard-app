import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../main.dart';
import '../md_zoom.dart';
import '../models.dart';

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

  Video? _video(AppState state) {
    try {
      return state.videos.firstWhere((v) => v.videoId == widget.videoId);
    } catch (_) {
      return null;
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

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(v.title ?? v.videoId,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Chat'),
            Tab(text: 'Chapters'),
            Tab(text: 'Transcript'),
          ]),
          actions: [
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
                      : '${v.chapters.length} chapters — tap one to read',
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
                        actions: const [TextSizeButtons(), SizedBox(width: 4)],
                      ),
                      body: ZoomMd(
                        data: [
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
      body: ZoomMd(data: content, scrollable: true),
    );
  }
}
