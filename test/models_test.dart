import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dashboard_app/models.dart';

void main() {
  test('Video model parsing and VideoSort', () {
    final v = Video(
      videoId: 'v123',
      title: 'Sample Video',
      savedAt: 1723700000000,
      openedAt: 1723750000000,
      addedAt: 1723650000000,
      extractedAt: 1723720000000,
    );

    expect(v.videoId, 'v123');
    expect(v.title, 'Sample Video');
    expect(v.openedAt, 1723750000000);
  });

  test('ModelInfo parses provider and modalities', () {
    final m = ModelInfo.fromJson({
      'id': 'gemini-3.7-flash',
      'name': 'Gemini 3.7 Flash',
      'provider': 'google',
      'context': 1048576,
      'inputModalities': ['text', 'image'],
      'outputModalities': ['text'],
    });

    expect(m.isGoogle, isTrue);
    expect(m.vision, isTrue);
    expect(m.provider, 'google');
  });

  test('SavedResult parses audio and hasAudio', () {
    final r1 = SavedResult.fromJson({
      'id': 1,
      'video_id': 'v123',
      'prompt_name': 'Key Takeaways',
      'content': '# Takeaways',
      'has_audio': true,
    });
    expect(r1.hasAudio, isTrue);

    final r2 = SavedResult.fromJson({
      'id': 2,
      'video_id': 'v123',
      'prompt_name': 'Executive Summary',
      'content': '# Summary',
      'audio': 'data:audio/mpeg;base64,BBBB',
    });
    expect(r2.hasAudio, isTrue);
    expect(r2.audio, 'data:audio/mpeg;base64,BBBB');
  });

  test('PlaylistInfo parses video list and total', () {
    final pl = PlaylistInfo.fromJson({
      'playlistId': 'PL12345',
      'title': 'AI Deep Dive',
      'owner': 'Phil',
      'total': 2,
      'videos': [
        {'videoId': 'vid1', 'title': 'Intro to LLMs', 'author': 'Phil'},
        {'videoId': 'vid2', 'title': 'Transformers', 'author': 'Phil'},
      ],
    });

    expect(pl.playlistId, 'PL12345');
    expect(pl.title, 'AI Deep Dive');
    expect(pl.videos.length, 2);
    expect(pl.videos[0].videoId, 'vid1');
    expect(PlaylistProcessMode.chapters.label, 'Chapters & Summaries');
    expect(PlaylistProcessMode.full.label, 'Full (Chapters + Prompts)');
  });
}
