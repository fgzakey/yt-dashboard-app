import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

/// Prefilled server address — the deployed Space. Only the app password is
/// needed on first run; override the URL in Settings to point elsewhere.
const String kDefaultServerUrl = 'https://fgza-yt-dashboard.hf.space';

class AppState extends ChangeNotifier {
  final ApiClient api = ApiClient();

  bool loadedPrefs = false;
  String model = 'google/gemini-2.5-flash';
  double temperature = 0.4;

  // Global text scale for rendered markdown (pinch to zoom, persisted).
  double mdScale = 1.0;

  List<Video> videos = [];
  List<PromptTemplate> prompts = []; // builtins + custom, builtins first
  List<ModelInfo> models = [];

  bool loadingVideos = false;
  String? videosError;

  Future<void> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final savedUrl = p.getString('baseUrl');
    api.baseUrl = (savedUrl == null || savedUrl.isEmpty) ? kDefaultServerUrl : savedUrl;
    api.password = p.getString('password') ?? '';
    model = p.getString('model') ?? model;
    temperature = p.getDouble('temperature') ?? 0.4;
    mdScale = p.getDouble('mdScale') ?? 1.0;
    loadedPrefs = true;
    notifyListeners();
  }

  Future<void> saveSettings({
    required String baseUrl,
    required String password,
    String? newModel,
    double? newTemperature,
  }) async {
    // Normalize: strip trailing slash.
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    api.baseUrl = url;
    api.password = password.trim();
    if (newModel != null) model = newModel;
    if (newTemperature != null) temperature = newTemperature;

    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', api.baseUrl);
    await p.setString('password', api.password);
    await p.setString('model', model);
    await p.setDouble('temperature', temperature);
    notifyListeners();
  }

  /// Live-update the markdown text scale during a pinch (no disk write).
  /// Bump the global text size by [delta] (e.g. ±0.1) and persist.
  Future<void> bumpMdScale(double delta) async {
    mdScale = double.parse((mdScale + delta).clamp(0.6, 3.0).toStringAsFixed(2));
    notifyListeners();
    await saveMdScale();
  }

  void previewMdScale(double v) {
    mdScale = v;
    notifyListeners();
  }

  /// Persist the markdown text scale (called when the pinch ends).
  Future<void> saveMdScale() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('mdScale', mdScale);
  }

  Future<void> setModel(String id) async {
    model = id;
    final p = await SharedPreferences.getInstance();
    await p.setString('model', id);
    notifyListeners();
  }

  // ---- Videos ----

  Future<void> refreshVideos() async {
    loadingVideos = true;
    videosError = null;
    notifyListeners();
    try {
      videos = await api.listVideos();
    } catch (e) {
      videosError = e.toString();
    }
    loadingVideos = false;
    notifyListeners();
  }

  Future<Video> addVideoFromUrl(String url) async {
    final v = await api.fetchTranscript(url);
    await api.saveVideo(v);
    await refreshVideos();
    return videos.firstWhere((x) => x.videoId == v.videoId, orElse: () => v);
  }

  Future<void> saveVideo(Video v) async {
    await api.saveVideo(v);
    notifyListeners();
  }

  Future<void> deleteVideo(String videoId) async {
    await api.deleteVideo(videoId);
    videos.removeWhere((v) => v.videoId == videoId);
    notifyListeners();
  }

  // ---- Prompts ----

  Future<void> refreshPrompts() async {
    final defaults = await api.listDefaultPrompts();
    List<PromptTemplate> custom = [];
    try {
      custom = await api.listPrompts();
    } catch (_) {}
    // DB prompts override builtins with the same id (same merge as the web).
    final customIds = custom.map((p) => p.id).toSet();
    prompts = [
      ...defaults.where((d) => !customIds.contains(d.id)),
      ...custom,
    ];
    notifyListeners();
  }

  Future<void> savePrompt(PromptTemplate p) async {
    await api.savePrompt(p);
    await refreshPrompts();
  }

  Future<void> deletePrompt(String id) async {
    await api.deletePrompt(id);
    await refreshPrompts();
  }

  // ---- Models ----

  Future<void> refreshModels() async {
    try {
      models = await api.listModels();
      notifyListeners();
    } catch (_) {}
  }

  // ---- Chat (same system prompt as the web dashboard) ----

  Future<ChatResponse> askVideo(Video v, List<ChatMessage> history) {
    final system = {
      'role': 'system',
      'content':
          "You are a helpful assistant answering questions about a specific YouTube video, using ONLY its transcript. If the answer isn't in the transcript, say so.\n\nVideo title: ${v.title}\n\nTRANSCRIPT:\n${v.text}",
    };
    return api.chat(
      model: model,
      messages: [
        system,
        ...history.map((m) => {'role': m.role, 'content': m.content}),
      ],
      temperature: temperature,
    );
  }

  Future<ChatResponse> runPrompt(Video v, PromptTemplate p) {
    final filled = p.fill(title: v.title ?? '', transcript: v.text);
    return api.chat(
      model: model,
      messages: [
        {'role': 'user', 'content': filled},
      ],
      temperature: temperature,
    );
  }
}
