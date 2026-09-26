import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/download_item.dart';
import '../models/download_options.dart';
import 'ffmpeg_commands.dart';
import 'stream_selection.dart';

/// ffmpeg 실행을 감싸는 주입 가능한 함수 타입. 반환값은 프로세스 종료 코드이며
/// 0이 성공이다. 실제 구현은 [defaultFfmpegRunner], 테스트에서는 페이크로 대체한다.
typedef FfmpegRunner = Future<int> Function(List<String> args);

/// SAF로 선택된 폴더에 파일을 쓰는 주입 가능한 함수 타입.
/// 실제 구현은 [defaultSafWriter], 테스트에서는 페이크로 대체한다.
typedef SafFileWriter = Future<void> Function({
  required String saveDirUri,
  required String fileName,
  required String sourceFilePath,
});

Future<int> defaultFfmpegRunner(List<String> args) async {
  final session = await FFmpegKit.executeWithArguments(args);
  final returnCode = await session.getReturnCode();
  return returnCode?.getValue() ?? -1;
}

Future<void> defaultSafWriter({
  required String saveDirUri,
  required String fileName,
  required String sourceFilePath,
}) async {
  final bytes = await File(sourceFilePath).readAsBytes();
  final mimeType = fileName.toLowerCase().endsWith('.mp3')
      ? 'audio/mpeg'
      : 'video/mp4';
  // saf 패키지 v2 API(saf-2.1.2)의 Saf().writeFileBytes(dirUri, name, mime, data)
  // 시그니처를 그대로 사용한다.
  await Saf().writeFileBytes(saveDirUri, fileName, mimeType, bytes);
}

/// youtube_explode_dart로 스트림을 내려받고, ffmpeg로 mp3 재인코딩 또는 mp4
/// 먹싱을 수행한 뒤, 결과 파일을 사용자가 지정한 위치(SAF) 또는 앱 기본 폴더에
/// 저장하는 서비스.
class DownloadService {
  static const int maxParallel = 3;
  int _running = 0;
  final _queue = <_Task>[];
  final _yt = YoutubeExplode();
  final FfmpegRunner _ffmpegRunner;
  final SafFileWriter _safWriter;

  DownloadService({
    FfmpegRunner? ffmpegRunner,
    SafFileWriter? safWriter,
  })  : _ffmpegRunner = ffmpegRunner ?? defaultFfmpegRunner,
        _safWriter = safWriter ?? defaultSafWriter;

  void enqueue({
    required DownloadItem item,
    required String fallbackSaveDir,
    String? saveDirUri,
    required void Function() onUpdate,
  }) {
    _queue.add(_Task(
      item: item,
      fallbackSaveDir: fallbackSaveDir,
      saveDirUri: saveDirUri,
      onUpdate: onUpdate,
    ));
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
    final tempFiles = <File>[];
    try {
      item.status = DownloadStatus.fetching;
      task.onUpdate();

      final video = await _yt.videos.get(item.url);
      final manifest = await _yt.videos.streamsClient.getManifest(video.id);
      final title = _sanitizeFileName(video.title);
      final tempDir = await getTemporaryDirectory();

      final audioStream = _pickAudioStream(manifest);
      if (audioStream == null) {
        throw StateError('오디오 스트림을 찾을 수 없습니다.');
      }

      late final String encodedPath;
      late final String finalFileName;

      if (item.format == DownloadFormat.mp3) {
        final audioTmp =
            File('${tempDir.path}/${item.id}_audio.${audioStream.container.name}');
        tempFiles.add(audioTmp);

        item.status = DownloadStatus.downloading;
        task.onUpdate();
        await _downloadStream(
          stream: audioStream,
          destination: audioTmp,
          onProgress: (received, total) {
            item.progress = total > 0 ? received / total : 0;
          },
          onSpeedUpdate: (label) => item.speedLabel = label,
          onUpdate: task.onUpdate,
        );

        item.status = DownloadStatus.processing;
        item.speedLabel = '';
        task.onUpdate();

        finalFileName = '$title.mp3';
        encodedPath = '${tempDir.path}/${item.id}_out.mp3';
        tempFiles.add(File(encodedPath));
        final exitCode = await _ffmpegRunner(buildMp3EncodeArgs(
          audioInputPath: audioTmp.path,
          outputPath: encodedPath,
          bitrateKbps: item.audioQuality!.bitrateKbps,
        ));
        if (exitCode != 0) {
          throw StateError('ffmpeg 오디오 인코딩 실패 (code $exitCode)');
        }
      } else {
        final videoStreams = manifest.videoOnly.toList();
        final candidates = videoStreams
            .map((s) => VideoStreamCandidate(
                  heightPx: s.videoResolution.height,
                  bitrateBitsPerSecond: s.bitrate.bitsPerSecond,
                ))
            .toList();
        final selection =
            selectVideoStream(candidates, item.videoQuality!.heightPx);
        if (selection == null) {
          throw StateError('영상 스트림을 찾을 수 없습니다.');
        }
        final videoStream = videoStreams[selection.candidateIndex];
        item.appliedHeightPx = selection.appliedHeightPx;

        final videoTmp =
            File('${tempDir.path}/${item.id}_video.${videoStream.container.name}');
        final audioTmp =
            File('${tempDir.path}/${item.id}_audio.${audioStream.container.name}');
        tempFiles.add(videoTmp);
        tempFiles.add(audioTmp);

        item.status = DownloadStatus.downloading;
        task.onUpdate();

        final combinedTotal =
            videoStream.size.totalBytes + audioStream.size.totalBytes;
        var videoReceived = 0;
        var audioReceived = 0;

        await _downloadStream(
          stream: videoStream,
          destination: videoTmp,
          onProgress: (received, total) {
            videoReceived = received;
            item.progress = combinedTotal > 0
                ? (videoReceived + audioReceived) / combinedTotal
                : 0;
          },
          onSpeedUpdate: (label) => item.speedLabel = label,
          onUpdate: task.onUpdate,
        );
        await _downloadStream(
          stream: audioStream,
          destination: audioTmp,
          onProgress: (received, total) {
            audioReceived = received;
            item.progress = combinedTotal > 0
                ? (videoReceived + audioReceived) / combinedTotal
                : 0;
          },
          onSpeedUpdate: (label) => item.speedLabel = label,
          onUpdate: task.onUpdate,
        );

        item.status = DownloadStatus.processing;
        item.speedLabel = '';
        task.onUpdate();

        finalFileName = '$title.mp4';
        encodedPath = '${tempDir.path}/${item.id}_out.mp4';
        tempFiles.add(File(encodedPath));
        final exitCode = await _ffmpegRunner(buildMp4MuxArgs(
          videoInputPath: videoTmp.path,
          audioInputPath: audioTmp.path,
          outputPath: encodedPath,
        ));
        if (exitCode != 0) {
          throw StateError('ffmpeg 먹싱 실패 (code $exitCode)');
        }
      }

      if (task.saveDirUri != null) {
        // Android SAF의 createDocument는 동일 이름 문서가 이미 있으면 자동으로
        // "(1)" 등을 붙여 새 이름을 만들어주므로, 앱에서 별도 중복 검사를
        // 하지 않는다. SAF 경로로 저장된 항목은 일반 파일시스템 경로가 없으므로
        // filePath는 null로 남긴다 (홈 화면의 "열기" 버튼이 자동으로 숨겨짐).
        await _safWriter(
          saveDirUri: task.saveDirUri!,
          fileName: finalFileName,
          sourceFilePath: encodedPath,
        );
        item.filePath = null;
      } else {
        final ext = finalFileName.split('.').last;
        final destPath = await _uniquePath(task.fallbackSaveDir, title, ext);
        await File(encodedPath).copy(destPath);
        item.filePath = destPath;
      }

      item.title = finalFileName;
      item.status = DownloadStatus.done;
      item.progress = 1.0;
      item.speedLabel = '';
    } catch (e) {
      item.status = DownloadStatus.error;
      item.errorMsg = _cleanError(e);
    } finally {
      for (final f in tempFiles) {
        if (await f.exists()) {
          await f.delete();
        }
      }
    }
    task.onUpdate();
  }

  Future<void> _downloadStream({
    required StreamInfo stream,
    required File destination,
    required void Function(int received, int total) onProgress,
    required void Function(String label) onSpeedUpdate,
    required void Function() onUpdate,
  }) async {
    final total = stream.size.totalBytes;
    var received = 0;
    var lastBytes = 0;
    final sw = Stopwatch()..start();
    final sink = destination.openWrite();
    try {
      await for (final chunk in _yt.videos.streamsClient.get(stream)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
        if (sw.elapsedMilliseconds > 400) {
          final elapsedSec = sw.elapsedMilliseconds / 1000;
          onSpeedUpdate(_formatSpeed((received - lastBytes) / elapsedSec));
          lastBytes = received;
          sw.reset();
          onUpdate();
        }
      }
    } finally {
      // close() flushes any buffered bytes before closing, so this alone
      // guarantees the file handle is released on both the success and
      // error paths (e.g. a network failure mid-transfer).
      await sink.close();
    }
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
  final String fallbackSaveDir;
  final String? saveDirUri;
  final void Function() onUpdate;
  _Task({
    required this.item,
    required this.fallbackSaveDir,
    required this.saveDirUri,
    required this.onUpdate,
  });
}
