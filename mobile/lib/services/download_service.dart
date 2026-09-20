import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/download_item.dart';

/// yt-dlp 바이너리를 Android assets에서 꺼내 실행하는 서비스.
/// yt-dlp ARM64 바이너리를 assets/yt-dlp에 넣어두면 됩니다.
class DownloadService {
  static const int maxParallel = 3;
  int _running = 0;
  final _queue = <_Task>[];

  // ── yt-dlp 바이너리 준비 ────────────────────────────
  static String? _ytDlpPath;

  static Future<String> _getYtDlpPath() async {
    if (_ytDlpPath != null) return _ytDlpPath!;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/yt-dlp');
    if (!file.existsSync()) {
      // assets에서 복사
      final data = await _readAsset('assets/yt-dlp');
      await file.writeAsBytes(data);
      await Process.run('chmod', ['+x', file.path]);
    }
    _ytDlpPath = file.path;
    return _ytDlpPath!;
  }

  static Future<List<int>> _readAsset(String path) async {
    // Flutter asset을 읽으려면 rootBundle을 써야 하지만
    // service layer에서는 File로 직접 접근 (APK unpack 후 경로)
    // 실제로는 lib/services/asset_helper.dart에서 rootBundle 주입
    throw UnimplementedError('asset_helper를 통해 주입하세요');
  }

  // ── 다운로드 큐 ──────────────────────────────────────
  void enqueue({
    required DownloadItem item,
    required String saveDir,
    required void Function() onUpdate,
  }) {
    final task = _Task(item: item, saveDir: saveDir, onUpdate: onUpdate);
    _queue.add(task);
    _tryNext();
  }

  void _tryNext() {
    while (_running < maxParallel && _queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      _running++;
      _run(task).then((_) {
        _running--;
        _tryNext();
      });
    }
  }

  Future<void> _run(_Task task) async {
    final item = task.item;
    try {
      item.status = DownloadStatus.fetching;
      task.onUpdate();

      final ytdlp = await _getYtDlpPath();
      final output = '${task.saveDir}/%(title)s.%(ext)s';

      // yt-dlp 실행: MP3 추출
      final args = [
        '--no-check-certificates',
        '-x',                          // 오디오 추출
        '--audio-format', 'mp3',
        '--audio-quality', '0',        // 최고 품질
        '--embed-thumbnail',           // 썸네일 임베드
        '--add-metadata',
        '--newline',                   // 진행률 파싱용
        '-o', output,
        item.url,
      ];

      final process = await Process.start(ytdlp, args);
      item.status = DownloadStatus.downloading;
      task.onUpdate();

      // stdout 파싱 → 진행률
      process.stdout.transform(const SystemEncoding().decoder).listen((line) {
        // [download]  65.3% of ~  5.23MiB at  1.20MiB/s ETA 00:02
        final pct = _parseProgress(line);
        if (pct != null) {
          item.progress = pct;
          final speed = _parseSpeed(line);
          if (speed != null) item.speedLabel = speed;
          task.onUpdate();
        }
        // 제목 파싱
        if (line.contains('[ExtractAudio]') || line.contains('Destination:')) {
          final match = RegExp(r'Destination: (.+)\.mp3').firstMatch(line);
          if (match != null) {
            final raw = match.group(1)!.split('/').last;
            item.title = raw;
            item.filePath = '${task.saveDir}/$raw.mp3';
            task.onUpdate();
          }
        }
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        item.status = DownloadStatus.done;
        item.progress = 1.0;
        item.speedLabel = '';
      } else {
        final err = await process.stderr.transform(const SystemEncoding().decoder).join();
        item.status = DownloadStatus.error;
        item.errorMsg = _cleanError(err);
      }
    } catch (e) {
      item.status = DownloadStatus.error;
      item.errorMsg = e.toString();
    }
    task.onUpdate();
  }

  double? _parseProgress(String line) {
    final m = RegExp(r'\s([\d.]+)%').firstMatch(line);
    if (m == null) return null;
    return (double.tryParse(m.group(1)!) ?? 0) / 100;
  }

  String? _parseSpeed(String line) {
    final m = RegExp(r'at\s+([\d.]+\s*\w+/s)').firstMatch(line);
    return m?.group(1);
  }

  String _cleanError(String raw) {
    // 첫 번째 ERROR: 줄만 추출
    final lines = raw.split('\n');
    for (final l in lines) {
      if (l.contains('ERROR:')) return l.replaceFirst(RegExp(r'.*ERROR:\s*'), '');
    }
    return raw.length > 120 ? '${raw.substring(0, 120)}...' : raw;
  }
}

class _Task {
  final DownloadItem item;
  final String saveDir;
  final void Function() onUpdate;
  _Task({required this.item, required this.saveDir, required this.onUpdate});
}
