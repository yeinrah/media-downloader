import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/widgets/save_location_bar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.dark()),
        home: Scaffold(body: child),
      );

  testWidgets('shows the display path', (tester) async {
    await tester.pumpWidget(wrap(SaveLocationBar(
      displayPath: '/sdcard/Music/MP3Downloader',
      onChangePressed: () {},
    )));

    expect(find.text('/sdcard/Music/MP3Downloader'), findsOneWidget);
  });

  testWidgets('tapping change button invokes callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(SaveLocationBar(
      displayPath: '/sdcard/Music/MP3Downloader',
      onChangePressed: () => tapped = true,
    )));

    await tester.tap(find.text('변경'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
