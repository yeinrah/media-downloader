import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Flutter assets에서 yt-dlp ARM64 바이너리를 앱 내부 저장소에 복사.
/// main()에서 한 번 호출하면 됩니다.
Future<String> prepareYtDlp() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/yt-dlp');

  if (!file.existsSync()) {
    final data = await rootBundle.load('assets/yt-dlp');
    await file.writeAsBytes(data.buffer.asUint8List());
    await Process.run('chmod', ['+x', file.path]);
  }
  return file.path;
}
