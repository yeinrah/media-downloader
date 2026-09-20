import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yt_downloader/main.dart';

void main() {
  testWidgets('App launches and shows home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const YtDownloaderApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
