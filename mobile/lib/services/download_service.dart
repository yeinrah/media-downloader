import 'dart:async';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/download_item.dart';

/// youtube_explode_dart로 오디오 스트림을 직접 내려받는 서비스.
/// 네이티브 바이너리(yt-dlp) 의존 없이 순수 Dart로 동작합니다.
///
/// YouTube는 오디오를 원본 코덱(AAC/m4a 또는 Opus/webm) 그대로 서빙하므로,
/// 별도의 오디오 인코더 없이는 진짜 .mp3로 재인코딩할 수 없습니다.
/// 재생 호환성이 가장 좋은 m4a(AAC)를 우선 선택하고, 없으면 최고 비트레이트
/// 오디오 스트림을 원본 확장자 그대로 저장합니다.
class DownloadService {
  static const int maxParallel = 3;
  int _running = 0;
  final _queue = <_Task>[];
  final _yt = YoutubeExplode();

  void enqueue({
    required DownloadItem item,
    required String saveDir,
    required void Function() onUpdate,
  }) {
    _queue.add(_Task(item: item, saveDir: saveDir, onUpdate: onUpdate));
    _tryNext();
  }

  void _tryNext() {
    while (_running < maxParallel && _queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      _running++;
      _run(task).whenComplete(() {
        _running--;
        _tryNext();
      });
    }
  }

  Future<void> _run(_Task task) async {
    final item = task.item;
    IOSink? sink;
    try {
      item.status = DownloadStatus.fetching;
      task.onUpdate();

      final video = await _yt.videos.get(item.url);
      final manifest = await _yt.videos.streamsClient.getManifest(video.id);
      final audio = _pickAudioStream(manifest);
      if (audio == null) {
        throw StateError('오디오 스트림을 찾을 수 없습니다.');
      }

      final title = _sanitizeFileName(video.title);
      final ext = audio.container.name;
      final filePath = await _uniquePath(task.saveDir, title, ext);
      item.title = '$title.$ext';
      item.filePath = filePath;

      item.status = DownloadStatus.downloading;
      task.onUpdate();

      final total = audio.size.totalBytes;
      var received = 0;
      var lastBytes = 0;
      final sw = Stopwatch()..start();

      sink = File(filePath).openWrite();
      await for (final chunk in _yt.videos.streamsClient.get(audio)) {
        sink.add(chunk);
        received += chunk.length;
        item.progress = total > 0 ? received / total : 0;

        if (sw.elapsedMilliseconds > 400) {
          final elapsedSec = sw.elapsedMilliseconds / 1000;
          item.speedLabel = _formatSpeed((received - lastBytes) / elapsedSec);
          lastBytes = received;
          sw.reset();
          task.onUpdate();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      item.status = DownloadStatus.done;
      item.progress = 1.0;
      item.speedLabel = '';
    } catch (e) {
      await sink?.close();
      item.status = DownloadStatus.error;
      item.errorMsg = _cleanError(e);
    }
    task.onUpdate();
  }

  AudioOnlyStreamInfo? _pickAudioStream(StreamManifest manifest) {
    final streams = manifest.audioOnly;
    if (streams.isEmpty) return null;
    final m4a = streams.where((s) => s.container == StreamContainer.mp4);
    return m4a.isNotEmpty
        ? m4a.reduce(
            (a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b)
        : streams.withHighestBitrate();
  }

  Future<String> _uniquePath(String dir, String title, String ext) async {
    var path = '$dir/$title.$ext';
    var n = 1;
    while (await File(path).exists()) {
      path = '$dir/$title ($n).$ext';
      n++;
    }
    return path;
  }

  String _sanitizeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.length > 100 ? cleaned.substring(0, 100) : cleaned;
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)}MB/s';
    }
    return '${(bytesPerSec / 1024).toStringAsFixed(0)}KB/s';
  }

  String _cleanError(Object e) {
    final raw = e.toString();
    return raw.length > 120 ? '${raw.substring(0, 120)}...' : raw;
  }

  void dispose() => _yt.close();
}

class _Task {
  final DownloadItem item;
  final String saveDir;
  final void Function() onUpdate;
  _Task({required this.item, required this.saveDir, required this.onUpdate});
}
