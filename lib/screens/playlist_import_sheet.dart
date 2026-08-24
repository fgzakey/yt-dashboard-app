import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';

class PlaylistImportSheet extends StatefulWidget {
  final String? initialUrl;
  const PlaylistImportSheet({super.key, this.initialUrl});

  @override
  State<PlaylistImportSheet> createState() => _PlaylistImportSheetState();
}

class _PlaylistImportSheetState extends State<PlaylistImportSheet> {
  final _urlCtrl = TextEditingController();
  final _langCtrl = TextEditingController();
  PlaylistProcessMode _mode = PlaylistProcessMode.none;
  String _method = 'auto';
  bool _replace = false;
  bool _showAdvanced = false;

  bool _enumerating = false;
  PlaylistInfo? _preview;
  String? _previewError;

  bool _importing = false;
  String _statusMessage = '';
  int _currentIndex = 0;
  int _totalCount = 0;
  final List<PlaylistRowStatus> _rows = [];
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      _urlCtrl.text = widget.initialUrl!;
      Future.microtask(_previewPlaylist);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _langCtrl.dispose();
    super.dispose();
  }

  Future<void> _previewPlaylist() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _enumerating = true;
      _previewError = null;
      _preview = null;
    });
    try {
      final state = context.read<AppState>();
      final info = await state.api.expandPlaylist(url);
      if (mounted) setState(() => _preview = info);
    } catch (e) {
      if (mounted) setState(() => _previewError = e.toString());
    }
    if (mounted) setState(() => _enumerating = false);
  }

  Future<void> _startImport() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;

    final state = context.read<AppState>();
    state.resetPlaylistImportAbort();

    setState(() {
      _importing = true;
      _completed = false;
      _statusMessage = 'Reading playlist…';
      _currentIndex = 0;
      _totalCount = _preview?.total ?? 0;
      _rows.clear();
    });

    try {
      final stream = state.api.streamPlaylistImport(
        url,
        lang: _langCtrl.text.trim().isEmpty ? null : _langCtrl.text.trim(),
        method: _method,
        replace: _replace,
      );

      await for (final event in stream) {
        if (state.isPlaylistImportAborted) break;
        final type = event['type']?.toString();

        if (type == 'status') {
          if (mounted) {
            setState(() {
              _statusMessage = event['message']?.toString() ?? 'Working…';
            });
          }
        } else if (type == 'playlist') {
          if (mounted) {
            setState(() {
              _totalCount = (event['total'] as num?)?.toInt() ?? _totalCount;
              _statusMessage = 'Importing transcripts (0/$_totalCount)…';
            });
          }
        } else if (type == 'video') {
          final idx = (event['index'] as num?)?.toInt() ?? (_currentIndex + 1);
          final tot = (event['total'] as num?)?.toInt() ?? _totalCount;
          final vidId = event['videoId']?.toString() ?? '';
          final title = event['title']?.toString() ?? vidId;
          final outcome = event['outcome']?.toString() ?? 'working';
          final message = event['message']?.toString();
          final words = (event['words'] as num?)?.toInt();

          if (mounted) {
            setState(() {
              _currentIndex = idx;
              _totalCount = tot;
              _statusMessage = '[$idx/$tot] $title';

              final existingRowIdx = _rows.indexWhere((r) => r.videoId == vidId);
              if (existingRowIdx >= 0) {
                _rows[existingRowIdx] = _rows[existingRowIdx].copyWith(
                  outcome: outcome,
                  message: message,
                  words: words,
                );
              } else {
                _rows.add(PlaylistRowStatus(
                  videoId: vidId,
                  title: title,
                  outcome: outcome,
                  message: message,
                  words: words,
                ));
              }
            });
          }
        } else if (type == 'error') {
          if (mounted) {
            setState(() {
              _statusMessage = 'Error: ${event['error']}';
            });
          }
        } else if (type == 'done') {
          break;
        }
      }

      await state.refreshVideos();
      final newlySavedIds = _rows
          .where((r) => r.outcome == 'saved' || (r.words != null && r.words! > 0))
          .map((r) => r.videoId)
          .toSet();

      final todoList = state.videos
          .where((v) => newlySavedIds.contains(v.videoId))
          .toList();

      if (!state.isPlaylistImportAborted &&
          _mode != PlaylistProcessMode.none &&
          todoList.isNotEmpty) {
        if (mounted) {
          setState(() {
            _statusMessage = 'Running ${_mode.label} on ${todoList.length} video(s)…';
          });
        }

        await state.runPlaylistBatchProcessing(
          todoList,
          _mode,
          onProgress: (current, total, title, status) {
            if (mounted) {
              setState(() {
                _currentIndex = current;
                _totalCount = total;
                _statusMessage = '[$current/$total] $status';

                final rowIdx = _rows.indexWhere((r) => r.title == title);
                if (rowIdx >= 0) {
                  _rows[rowIdx] = _rows[rowIdx].copyWith(message: status);
                }
              });
            }
          },
        );

        await state.refreshVideos();
      }

      if (mounted) {
        setState(() {
          _importing = false;
          _completed = true;
          _statusMessage = state.isPlaylistImportAborted
              ? 'Import cancelled.'
              : 'Playlist import finished!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importing = false;
          _statusMessage = 'Import error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = context.watch<AppState>();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.playlist_play, color: scheme.primary, size: 28),
                  const SizedBox(width: 8),
                  Text('Import YouTube Playlist',
                      style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!_importing && !_completed) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlCtrl,
                        decoration: InputDecoration(
                          hintText: 'https://www.youtube.com/playlist?list=PL...',
                          labelText: 'Playlist URL or ID',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: _urlCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => setState(() {
                                    _urlCtrl.clear();
                                    _preview = null;
                                  }),
                                )
                              : null,
                        ),
                        onSubmitted: (_) => _previewPlaylist(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.tonal(
                      tooltip: 'Paste from clipboard',
                      icon: const Icon(Icons.paste),
                      onPressed: () async {
                        final data =
                            await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          _urlCtrl.text = data!.text!.trim();
                          _previewPlaylist();
                        }
                      },
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: _enumerating ? null : _previewPlaylist,
                      child: _enumerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Preview'),
                    ),
                  ],
                ),
                if (_previewError != null) ...[
                  const SizedBox(height: 8),
                  Text(_previewError!, style: TextStyle(color: scheme.error)),
                ],
                if (_preview != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _preview!.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (_preview!.owner != null &&
                                _preview!.owner!.isNotEmpty)
                              _preview!.owner!,
                            '${_preview!.total} videos',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text('AI Preprocessing Mode',
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: PlaylistProcessMode.values.map((m) {
                    final selected = _mode == m;
                    return ChoiceChip(
                      label: Text(m.label),
                      selected: selected,
                      onSelected: (val) {
                        if (val) setState(() => _mode = m);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showAdvanced
                            ? Icons.arrow_drop_down
                            : Icons.arrow_right,
                        size: 20,
                      ),
                      Text('Advanced options',
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                if (_showAdvanced) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('Replace existing transcripts'),
                    subtitle: const Text('Re-fetch videos already in library'),
                    value: _replace,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _replace = v ?? false),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _method,
                          decoration: const InputDecoration(
                            labelText: 'Fetch method',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'auto', child: Text('Auto')),
                            DropdownMenuItem(
                                value: 'innertube', child: Text('InnerTube')),
                            DropdownMenuItem(
                                value: 'timedtext', child: Text('TimedText')),
                          ],
                          onChanged: (v) =>
                              setState(() => _method = v ?? 'auto'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _langCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Language (optional)',
                            hintText: 'en, es, etc.',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text(_preview != null
                        ? 'Import ${_preview!.total} videos (${_mode.label})'
                        : 'Import Playlist'),
                    onPressed: _urlCtrl.text.trim().isEmpty ? null : _startImport,
                  ),
                ),
              ],
              if (_importing || _completed) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _statusMessage,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_importing)
                            TextButton.icon(
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              label: const Text('Cancel'),
                              onPressed: () => state.cancelPlaylistImport(),
                            ),
                        ],
                      ),
                      if (_importing) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _totalCount > 0
                              ? (_currentIndex / _totalCount).clamp(0.0, 1.0)
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 280,
                  child: ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = _rows[i];
                      final icon = switch (r.outcome) {
                        'saved' => Icon(Icons.check_circle,
                            color: scheme.primary, size: 18),
                        'skipped' => Icon(Icons.remove_circle_outline,
                            color: scheme.outline, size: 18),
                        'failed' =>
                          Icon(Icons.error_outline, color: scheme.error, size: 18),
                        _ => const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      };
                      return ListTile(
                        dense: true,
                        leading: icon,
                        title: Text(r.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: r.message != null ? Text(r.message!) : null,
                        trailing: r.words != null
                            ? Text('${r.words} words',
                                style: theme.textTheme.bodySmall)
                            : null,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (_completed)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}