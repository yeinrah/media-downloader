import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/models/download_item.dart';
import 'package:yt_downloader/models/download_options.dart';
import 'package:yt_downloader/widgets/download_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.dark()),
        home: Scaffold(body: child),
      );

  testWidgets('shows processing label and indeterminate progress bar', (tester) async {
    final item = DownloadItem(
      id: '1',
      url: 'https://example.com',
      format: DownloadFormat.mp3,
      audioQuality: AudioQuality.kbps192,
      status: DownloadStatus.processing,
      title: 'test.mp3',
    );

    await tester.pumpWidget(wrap(DownloadCard(item: item, onRemove: () {})));

    expect(find.text('변환 중'), findsOneWidget);
    final progressBar =
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(progressBar.value, isNull);
  });
}
