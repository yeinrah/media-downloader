import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/models/download_options.dart';
import 'package:yt_downloader/widgets/format_quality_selector.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows audio quality dropdown when format is mp3', (tester) async {
    await tester.pumpWidget(wrap(FormatQualitySelector(
      format: DownloadFormat.mp3,
      audioQuality: AudioQuality.kbps192,
      videoQuality: VideoQuality.q720p,
      onFormatChanged: (_) {},
      onAudioQualityChanged: (_) {},
      onVideoQualityChanged: (_) {},
    )));

    expect(find.text('192 kbps'), findsOneWidget);
    expect(find.text('720p'), findsNothing);
  });

  testWidgets('shows video quality dropdown when format is mp4', (tester) async {
    await tester.pumpWidget(wrap(FormatQualitySelector(
      format: DownloadFormat.mp4,
      audioQuality: AudioQuality.kbps192,
      videoQuality: VideoQuality.q720p,
      onFormatChanged: (_) {},
      onAudioQualityChanged: (_) {},
      onVideoQualityChanged: (_) {},
    )));

    expect(find.text('720p'), findsOneWidget);
    expect(find.text('192 kbps'), findsNothing);
  });

  testWidgets('selecting mp4 in format dropdown calls onFormatChanged', (tester) async {
    DownloadFormat? changed;
    await tester.pumpWidget(wrap(FormatQualitySelector(
      format: DownloadFormat.mp3,
      audioQuality: AudioQuality.kbps192,
      videoQuality: VideoQuality.q720p,
      onFormatChanged: (v) => changed = v,
      onAudioQualityChanged: (_) {},
      onVideoQualityChanged: (_) {},
    )));

    await tester.tap(find.text('MP3 (오디오)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MP4 (영상)').last);
    await tester.pumpAndSettle();

    expect(changed, DownloadFormat.mp4);
  });
}
