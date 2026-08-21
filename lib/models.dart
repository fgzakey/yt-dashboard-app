// Data models mirroring the dashboard's API shapes.

class Video {
  final String videoId;
  String? title;
  String? author;
  String? language;
  String? url;
  int wordCount;
  String text;
  List<dynamic> segments;
  List<ChatMessage> chat;
  List<dynamic> chapters;
  int? savedAt; // epoch ms — `updated_at`, i.e. LAST MODIFIED, not last opened
  // Library sort keys, all epoch ms and all nullable: null means the event never
  // happened (never opened, never extracted), which is different from "long ago"
  // and is what puts a row in the tail of a sorted list rather than at 1970.
  int? addedAt; // `created_at`
  int? openedAt; // `last_opened_at`, written only by touchVideo
  int? extractedAt; // MAX(results.created_at) for this video

  Video({
    required this.videoId,
    this.title,
    this.author,
    this.language,
    this.url,
    this.wordCount = 0,
    this.text = '',
    List<dynamic>? segments,
    List<ChatMessage>? chat,
    List<dynamic>? chapters,
    this.savedAt,
    this.addedAt,
    this.openedAt,
    this.extractedAt,
  })  : segments = segments ?? [],
        chat = chat ?? [],
        chapters = chapters ?? [];

  factory Video.fromJson(Map<String, dynamic> j) => Video(
        videoId: j['videoId'] as String,
        title: j['title'] as String?,
        author: j['author'] as String?,
        language: j['language'] as String?,
        url: j['url'] as String?,
        wordCount: (j['wordCount'] as num?)?.toInt() ?? 0,
        text: j['text'] as String? ?? '',
        segments: (j['segments'] as List?) ?? [],
        chat: ((j['chat'] as List?) ?? [])
            .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        chapters: (j['chapters'] as List?) ?? [],
        savedAt: (j['savedAt'] as num?)?.toInt(),
        addedAt: (j['addedAt'] as num?)?.toInt(),
        openedAt: (j['openedAt'] as num?)?.toInt(),
        extractedAt: (j['extractedAt'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'author': author,
        'language': language,
        'url': url,
        'wordCount': wordCount,
        'text': text,
        'segments': segments,
        'chat': chat.map((m) => m.toJson()).toList(),
        'chapters': chapters,
      };

  /// Transcript text for chapter [i], sliced by timestamp — chapters carry a
  /// `start` (seconds); a chapter owns segments in [start, next.start). Falls
  /// back to the whole transcript when there are no timestamps.
  String chapterText(int i, {int? maxChars}) {
    if (i < 0 || i >= chapters.length) return '';
    final start = ((chapters[i] as Map)['start'] as num?)?.toDouble() ?? 0;
    final end = i + 1 < chapters.length
        ? ((chapters[i + 1] as Map)['start'] as num?)?.toDouble() ??
            double.infinity
        : double.infinity;
    final timed = segments.any((s) => (s as Map)['start'] != null);
    final buf = StringBuffer();
    if (timed) {
      for (final s in segments) {
        final t = (s as Map)['start'];
        final ts = t is num ? t.toDouble() : null;
        if (ts == null || ts < start || ts >= end) continue;
        if (buf.isNotEmpty) buf.write(' ');
        buf.write((s['text'] ?? '').toString());
        if (maxChars != null && buf.length > maxChars) break;
      }
    } else {
      buf.write(text);
    }
    var out = buf.toString();
    if (maxChars != null && out.length > maxChars) out = out.substring(0, maxChars);
    return out;
  }
}

class ChatMessage {
  final String role; // user | assistant
  final String content;
  final String? model;
  final String? cost;

  ChatMessage({required this.role, required this.content, this.model, this.cost});

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: j['role'] as String? ?? 'user',
        content: j['content'] as String? ?? '',
        model: j['model'] as String?,
        cost: j['cost']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (model != null) 'model': model,
        if (cost != null) 'cost': cost,
      };
}

class PromptTemplate {
  final String id;
  String name;
  String description;
  String template;
  final bool builtin;

  PromptTemplate({
    required this.id,
    required this.name,
    this.description = '',
    this.template = '',
    this.builtin = false,
  });

  factory PromptTemplate.fromJson(Map<String, dynamic> j) => PromptTemplate(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        template: j['template'] as String? ?? '',
        builtin: j['builtin'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'template': template,
      };

  /// Same substitution as lib/prompts.js fillTemplate on the web.
  String fill({required String title, required String transcript}) => template
      .replaceAll('{{title}}', title)
      .replaceAll('{{transcript}}', transcript);
}

class SavedResult {
  final dynamic id;
  final String? videoId;
  final String? videoTitle;
  final String? promptName;
  final String content;
  final String? model;
  final String? cost;
  final String? createdAt;

  SavedResult({
    this.id,
    this.videoId,
    this.videoTitle,
    this.promptName,
    required this.content,
    this.model,
    this.cost,
    this.createdAt,
  });

  factory SavedResult.fromJson(Map<String, dynamic> j) => SavedResult(
        id: j['id'],
        videoId: j['video_id'] as String?,
        videoTitle: j['video_title'] as String?,
        promptName: j['prompt_name'] as String?,
        content: j['content'] as String? ?? '',
        model: j['model'] as String?,
        cost: j['cost']?.toString(),
        createdAt: j['created_at']?.toString(),
      );
}

class ModelInfo {
  final String id;
  final String name;
  final int? context;
  final String? promptPrice;
  final String? completionPrice;
  final List<String> inputModalities;
  final List<String> outputModalities;
  final String provider;

  ModelInfo({
    required this.id,
    required this.name,
    this.context,
    this.promptPrice,
    this.completionPrice,
    this.inputModalities = const [],
    this.outputModalities = const [],
    this.provider = 'openrouter',
  });

  bool get vision => inputModalities.contains('image');
  bool get isGoogle =>
      provider == 'google' ||
      id.startsWith('google/') ||
      id.startsWith('gemini') ||
      id.startsWith('imagen');

  factory ModelInfo.fromJson(Map<String, dynamic> j) => ModelInfo(
        id: j['id'] as String,
        name: j['name'] as String? ?? j['id'] as String,
        context: (j['context'] as num?)?.toInt(),
        promptPrice: j['promptPrice']?.toString(),
        completionPrice: j['completionPrice']?.toString(),
        inputModalities: ((j['inputModalities'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
        outputModalities: ((j['outputModalities'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
        provider: j['provider']?.toString() ??
            ((j['id']?.toString().startsWith('gemini') == true ||
                    j['id']?.toString().startsWith('google/') == true)
                ? 'google'
                : 'openrouter'),
      );
}

class ChatResponse {
  final String content;
  final String? model;
  final Map<String, dynamic>? usage;

  ChatResponse({required this.content, this.model, this.usage});

  /// USD cost string, from OpenRouter's usage.cost when present.
  String? get cost {
    final c = usage?['cost'];
    if (c == null) return null;
    final v = (c as num).toDouble();
    if (v == 0) return null;
    return v < 0.01 ? '\$${v.toStringAsFixed(6)}' : '\$${v.toStringAsFixed(4)}';
  }
}

/// A syntopical synthesis essay from the knowledge graph (served by
/// /api/essays). The [body] is Markdown; [targetTitle] is the idea/theme the
/// essay synthesizes across the library.
class Essay {
  final dynamic id;
  final String slug;
  final String title;
  final String body;
  final String? targetTitle;
  final String? targetType;
  final String? updatedAt;

  Essay({
    this.id,
    required this.slug,
    required this.title,
    required this.body,
    this.targetTitle,
    this.targetType,
    this.updatedAt,
  });

  factory Essay.fromJson(Map<String, dynamic> j) => Essay(
        id: j['id'],
        slug: j['slug']?.toString() ?? '',
        title: j['title']?.toString() ?? 'Untitled essay',
        body: j['body']?.toString() ?? '',
        targetTitle: j['target_title']?.toString(),
        targetType: j['target_type']?.toString(),
        updatedAt: j['updated_at']?.toString(),
      );
}

// ---- Workspaces / Multi-user databases ----

class WorkspaceInfo {
  final String? owner; // null for canon
  final String name;
  final String kind; // canon | fork | clean | external
  final String label;
  final bool isCanon;
  final bool active;
  final bool mine;
  final bool canWrite;
  final bool canDelete;
  final int books;
  final int videos;
  final int results;
  final int boards;
  final int scenes;

  WorkspaceInfo({
    this.owner,
    required this.name,
    this.kind = 'fork',
    required this.label,
    this.isCanon = false,
    this.active = false,
    this.mine = true,
    this.canWrite = true,
    this.canDelete = false,
    this.books = 0,
    this.videos = 0,
    this.results = 0,
    this.boards = 0,
    this.scenes = 0,
  });

  factory WorkspaceInfo.fromJson(Map<String, dynamic> j) => WorkspaceInfo(
        owner: j['owner'] as String?,
        name: j['name']?.toString() ?? 'canon',
        kind: j['kind']?.toString() ?? 'canon',
        label: j['label']?.toString() ?? (j['name']?.toString() ?? 'canon'),
        isCanon: j['isCanon'] as bool? ?? (j['kind'] == 'canon'),
        active: j['active'] as bool? ?? false,
        mine: j['mine'] as bool? ?? true,
        canWrite: j['canWrite'] as bool? ?? true,
        canDelete: j['canDelete'] as bool? ?? false,
        books: (j['books'] as num?)?.toInt() ?? 0,
        videos: (j['videos'] as num?)?.toInt() ?? 0,
        results: (j['results'] as num?)?.toInt() ?? 0,
        boards: (j['boards'] as num?)?.toInt() ?? 0,
        scenes: (j['scenes'] as num?)?.toInt() ?? 0,
      );
}

class WorkspacesResponse {
  final String member;
  final bool admin;
  final WorkspaceInfo? active;
  final List<WorkspaceInfo> workspaces;

  WorkspacesResponse({
    this.member = 'admin',
    this.admin = true,
    this.active,
    this.workspaces = const [],
  });

  factory WorkspacesResponse.fromJson(Map<String, dynamic> j) => WorkspacesResponse(
        member: j['member']?.toString() ?? 'admin',
        admin: j['admin'] as bool? ?? false,
        active: j['active'] is Map
            ? WorkspaceInfo.fromJson(Map<String, dynamic>.from(j['active']))
            : null,
        workspaces: ((j['workspaces'] as List?) ?? [])
            .map((w) => WorkspaceInfo.fromJson(Map<String, dynamic>.from(w)))
            .toList(),
      );
}

// ---- Mnemonic scenes ----

class MnemonicSource {
  final String sourceKind; // book | video
  final String sourceId;
  final String sourceTitle;
  final int imageCount;
  final int boardCount;
  final String? latest;

  MnemonicSource({
    required this.sourceKind,
    required this.sourceId,
    required this.sourceTitle,
    this.imageCount = 0,
    this.boardCount = 0,
    this.latest,
  });

  factory MnemonicSource.fromJson(Map<String, dynamic> j) => MnemonicSource(
        sourceKind: j['source_kind']?.toString() ?? 'video',
        sourceId: j['source_id']?.toString() ?? '',
        sourceTitle: j['source_title']?.toString() ?? '(untitled source)',
        imageCount: (j['image_count'] as num?)?.toInt() ?? 0,
        boardCount: (j['board_count'] as num?)?.toInt() ?? 0,
        latest: j['latest']?.toString(),
      );
}

class MnemonicHotspot {
  final int i;
  final String heading;
  final String theme;
  final String colorHex;
  final List<String> points;
  final double? x;
  final double? y;
  final String placed; // vision | legend

  MnemonicHotspot({
    required this.i,
    required this.heading,
    this.theme = '',
    this.colorHex = '',
    this.points = const [],
    this.x,
    this.y,
    this.placed = 'legend',
  });

  factory MnemonicHotspot.fromJson(Map<String, dynamic> j) => MnemonicHotspot(
        i: (j['i'] as num?)?.toInt() ?? 0,
        heading: j['heading']?.toString() ?? '',
        theme: j['theme']?.toString() ?? '',
        colorHex: j['color']?.toString() ?? '',
        points: ((j['points'] as List?) ?? []).map((p) => p.toString()).toList(),
        x: (j['x'] as num?)?.toDouble(),
        y: (j['y'] as num?)?.toDouble(),
        placed: j['placed']?.toString() ?? 'legend',
      );
}

class MnemonicScene {
  final dynamic id;
  final String sourceKind;
  final String sourceId;
  final String sourceTitle;
  final String boardKey;
  final String variant;
  final String? style;
  final String? styleName;
  final String? model;
  final int? width;
  final int? height;
  final String? sourceResolution;
  final List<MnemonicHotspot> hotspots;
  final String? createdAt;
  final int imageChars;
  final String? image; // data URL, only on single-row fetch

  MnemonicScene({
    this.id,
    required this.sourceKind,
    required this.sourceId,
    required this.sourceTitle,
    required this.boardKey,
    this.variant = 'clean',
    this.style,
    this.styleName,
    this.model,
    this.width,
    this.height,
    this.sourceResolution,
    this.hotspots = const [],
    this.createdAt,
    this.imageChars = 0,
    this.image,
  });

  factory MnemonicScene.fromJson(Map<String, dynamic> j) {
    final image = j['image']?.toString();
    return MnemonicScene(
      id: j['id'],
      sourceKind: j['source_kind']?.toString() ?? 'video',
      sourceId: j['source_id']?.toString() ?? '',
      sourceTitle: j['source_title']?.toString() ?? '(untitled source)',
      boardKey: j['board_key']?.toString() ?? '',
      variant: j['variant']?.toString() ?? 'clean',
      style: j['style']?.toString(),
      styleName: j['style_name']?.toString(),
      model: j['model']?.toString(),
      width: (j['width'] as num?)?.toInt(),
      height: (j['height'] as num?)?.toInt(),
      sourceResolution: j['source_resolution']?.toString(),
      hotspots: ((j['hotspots'] as List?) ?? [])
          .map((h) => MnemonicHotspot.fromJson(Map<String, dynamic>.from(h)))
          .toList(),
      createdAt: j['created_at']?.toString(),
      imageChars: (j['image_chars'] as num?)?.toInt() ?? image?.length ?? 0,
      image: image,
    );
  }
}
