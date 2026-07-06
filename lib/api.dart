import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Client for the YT Dashboard backend (the Hugging Face Space).
///
/// Auth: the dashboard's middleware accepts a `yt_auth=<password>` cookie, so
/// after validating the password once via POST /api/login we simply attach
/// that cookie header to every request — no cookie jar needed.
class ApiClient {
  String baseUrl; // e.g. https://<user>-<space>.hf.space  (no trailing slash)
  String password;

  ApiClient({this.baseUrl = '', this.password = ''});

  bool get configured => baseUrl.isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (password.isNotEmpty) 'Cookie': 'yt_auth=$password',
      };

  Never _fail(http.Response res) {
    String msg = 'HTTP ${res.statusCode}';
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['error'] != null) msg = j['error'].toString();
    } catch (_) {}
    throw ApiException(msg, res.statusCode);
  }

  Map<String, dynamic> _json(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) _fail(res);
    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  /// Validates the password. Throws on failure.
  Future<void> login() async {
    final res = await http.post(
      _uri('/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'password': password}),
    );
    if (res.statusCode != 200) _fail(res);
  }

  // ---- Transcript ----

  Future<Video> fetchTranscript(String url, {String? lang, String method = 'auto'}) async {
    final res = await http
        .get(_uri('/api/transcript', {
          'url': url,
          if (lang != null && lang.isNotEmpty) 'lang': lang,
          'method': method,
        }), headers: _headers)
        .timeout(const Duration(seconds: 150));
    final j = _json(res);
    if (j['error'] != null) throw ApiException(j['error'].toString(), res.statusCode);
    return Video.fromJson(j);
  }

  // ---- Videos ----

  Future<List<Video>> listVideos() async {
    final res = await http.get(_uri('/api/db/videos'), headers: _headers);
    final j = _json(res);
    return ((j['videos'] as List?) ?? [])
        .map((v) => Video.fromJson(Map<String, dynamic>.from(v)))
        .toList();
  }

  Future<void> saveVideo(Video v) async {
    final res = await http.post(_uri('/api/db/videos'),
        headers: _headers, body: jsonEncode(v.toJson()));
    _json(res);
  }

  Future<void> deleteVideo(String videoId) async {
    final res = await http.delete(_uri('/api/db/videos', {'id': videoId}),
        headers: _headers);
    _json(res);
  }

  // ---- Prompts ----

  Future<List<PromptTemplate>> listPrompts() async {
    final res = await http.get(_uri('/api/db/prompts'), headers: _headers);
    final j = _json(res);
    return ((j['prompts'] as List?) ?? [])
        .map((p) => PromptTemplate.fromJson(Map<String, dynamic>.from(p)))
        .toList();
  }

  /// Built-in default prompts (requires the /api/prompts/defaults route on the
  /// dashboard). Returns [] if the route doesn't exist yet.
  Future<List<PromptTemplate>> listDefaultPrompts() async {
    try {
      final res = await http.get(_uri('/api/prompts/defaults'), headers: _headers);
      if (res.statusCode != 200) return [];
      final j = _json(res);
      return ((j['prompts'] as List?) ?? [])
          .map((p) => PromptTemplate.fromJson(Map<String, dynamic>.from(p)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePrompt(PromptTemplate p) async {
    final res = await http.post(_uri('/api/db/prompts'),
        headers: _headers, body: jsonEncode(p.toJson()));
    _json(res);
  }

  Future<void> deletePrompt(String id) async {
    final res = await http.delete(_uri('/api/db/prompts', {'id': id}),
        headers: _headers);
    _json(res);
  }

  // ---- Results ----

  Future<List<SavedResult>> listResults({String query = '', String? videoId}) async {
    final res = await http.get(
        _uri('/api/db/results', {
          if (videoId != null) 'videoId': videoId,
          if (query.isNotEmpty) 'q': query,
        }),
        headers: _headers);
    final j = _json(res);
    return ((j['results'] as List?) ?? [])
        .map((r) => SavedResult.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> saveResult({
    required String content,
    String? videoId,
    String? videoTitle,
    String? promptName,
    String? model,
    String? cost,
  }) async {
    final res = await http.post(_uri('/api/db/results'),
        headers: _headers,
        body: jsonEncode({
          'content': content,
          'videoId': videoId,
          'videoTitle': videoTitle,
          'promptName': promptName,
          'model': model,
          'cost': cost,
        }));
    _json(res);
  }

  // ---- Models & chat ----

  Future<List<ModelInfo>> listModels() async {
    final res = await http.get(_uri('/api/models'), headers: _headers);
    final j = _json(res);
    return ((j['models'] as List?) ?? [])
        .map((m) => ModelInfo.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<ChatResponse> chat({
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.4,
  }) async {
    final res = await http
        .post(_uri('/api/chat'),
            headers: _headers,
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'temperature': temperature,
            }))
        .timeout(const Duration(minutes: 5));
    final j = _json(res);
    return ChatResponse(
      content: j['content'] as String? ?? '',
      model: j['model'] as String?,
      usage: j['usage'] == null ? null : Map<String, dynamic>.from(j['usage']),
    );
  }
}

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, this.status);
  @override
  String toString() => message;
}
