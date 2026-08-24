import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../main.dart';
import '../models.dart';
import '../md_toc_view.dart';
import 'past_results.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  List<SavedResult> _results = [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await context
          .read<AppState>()
          .api
          .listResults(query: _search.text.trim());
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved results'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search title, prompt, or content…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? Center(child: Text('Error: $_error'))
                : _results.isEmpty && !_loading
                    ? const Center(child: Text('No saved results.'))
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _results[i];
                          return ListTile(
                            leading: Icon(
                              r.hasAudio
                                  ? Icons.audiotrack
                                  : Icons.description_outlined,
                              color: r.hasAudio
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(r.promptName ?? 'Result',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [
                                if (r.videoTitle != null) r.videoTitle!,
                                if (r.model != null) r.model!,
                                if (r.cost != null) r.cost!,
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: r.hasAudio
                                ? Icon(Icons.download_for_offline_outlined,
                                    size: 20,
                                    color: Theme.of(context).colorScheme.primary)
                                : null,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => _ResultDetail(result: r)),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ResultDetail extends StatelessWidget {
  final SavedResult result;
  const _ResultDetail({required this.result});

  Future<void> _exportAudio(BuildContext context) async {
    showSnack(context, 'Fetching audio…');
    try {
      final state = context.read<AppState>();
      final bytes = await state.api.fetchVideoResultAudioBytes(result.id);
      if (bytes == null || bytes.isEmpty) {
        if (context.mounted) showSnack(context, 'Audio data not found on server.');
        return;
      }
      final name = downloadName(
        title: result.videoTitle ?? 'Audio',
        kind: result.promptName ?? 'Narration',
        date: DateTime.tryParse(result.createdAt ?? ''),
        ext: 'mp3',
      );
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'audio/mpeg', name: name)],
        subject:
            '${result.videoTitle ?? 'Audio'} — ${result.promptName ?? 'Narration'}',
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      if (context.mounted) showSnack(context, 'Failed to export audio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(result.promptName ?? 'Result',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          const TextSizeButtons(),
          if (result.hasAudio)
            IconButton(
              tooltip: 'Export Audio (.mp3)',
              icon: const Icon(Icons.audiotrack),
              onPressed: () => _exportAudio(context),
            ),
          IconButton(
            tooltip: 'Copy Markdown',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result.content));
              showSnack(context, 'Copied.');
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result.videoTitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(result.videoTitle!,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          Expanded(child: MdWithToc(data: result.content)),
        ],
      ),
    );
  }
}
