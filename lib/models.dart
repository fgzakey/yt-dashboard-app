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
  int? savedAt; // epoch ms

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

  ModelInfo({
    required this.id,
    required this.name,
    this.context,
    this.promptPrice,
    this.completionPrice,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> j) => ModelInfo(
        id: j['id'] as String,
        name: j['name'] as String? ?? j['id'] as String,
        context: (j['context'] as num?)?.toInt(),
        promptPrice: j['promptPrice']?.toString(),
        completionPrice: j['completionPrice']?.toString(),
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
