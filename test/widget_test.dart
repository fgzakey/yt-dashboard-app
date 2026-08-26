import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yt_dashboard_app/app_state.dart';
import 'package:yt_dashboard_app/main.dart';
import 'package:yt_dashboard_app/models.dart';
import 'package:yt_dashboard_app/screens/videos_screen.dart';

void main() {
  test('VideoSort keyOf and sortStamp', () {
    final v = Video(
      videoId: 'test-1',
      title: 'Sample Video',
      savedAt: 1723700000000,
      openedAt: 1723750000000,
      addedAt: 1723650000000,
      extractedAt: 1723720000000,
    );

    expect(VideoSort.savedAt.keyOf(v), 1723700000000);
    expect(VideoSort.opened.keyOf(v), 1723750000000);
    expect(VideoSort.added.keyOf(v), 1723650000000);
    expect(VideoSort.extracted.keyOf(v), 1723720000000);

    expect(sortStamp(v, VideoSort.savedAt), '');
    expect(sortStamp(v, VideoSort.opened), isNotEmpty);
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
      'prompt_name': 'Key Ideas',
      'content': '# Ideas',
      'has_audio': true,
    });
    expect(r1.hasAudio, isTrue);

    final r2 = SavedResult.fromJson({
      'id': 2,
      'prompt_name': 'Executive Summary',
      'content': '# Summary',
      'audio': 'data:audio/mpeg;base64,AAAA',
    });
    expect(r2.hasAudio, isTrue);
    expect(r2.audio, 'data:audio/mpeg;base64,AAAA');
  });

  test('PlaylistProcessMode labels', () {
    expect(PlaylistProcessMode.none.label, 'Transcripts only');
    expect(PlaylistProcessMode.chapters.label, 'Chapters & Summaries');
    expect(PlaylistProcessMode.full.label, 'Full (Chapters + Prompts)');
  });

  testWidgets('App boots to the home shell', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'password': 'test'});

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState()..loadPrefs(),
        child: const YtDashboardApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(NavigationBar), matching: find.text('Videos')),
        findsOneWidget);
  });
}
