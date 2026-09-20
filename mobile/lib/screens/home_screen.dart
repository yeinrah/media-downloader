import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:open_filex/open_filex.dart';
import '../models/download_item.dart';
import '../services/asset_helper.dart';
import '../widgets/download_card.dart';
import '../widgets/app_icon_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController();
  final _items = <DownloadItem>[];
  final _uuid = const Uuid();
  String? _ytDlpPath;
  String? _saveDir;
  bool _ready = false;
  int _activeCount = 0;
  static const int _maxParallel = 3;
  final _queue = <DownloadItem>[];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 권한
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();

    // yt-dlp 바이너리 준비
    try {
      _ytDlpPath = await prepareYtDlp();
    } catch (e) {
      _showSnack('yt-dlp 준비 실패: $e');
      return;
    }

    // 저장 경로: /sdcard/Music/MP3Downloader
    final ext = await getExternalStorageDirectory();
    _saveDir = '${ext?.parent.parent.parent.parent.path ?? '/sdcard'}/Music/MP3Downloader';
    await Directory(_saveDir!).create(recursive: true);

    setState(() => _ready = true);
  }

  void _addUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http')) {
      _showSnack('올바른 URL을 입력해 주세요.');
      return;
    }
    final item = DownloadItem(
      id: _uuid.v4(),
      url: url,
      title: _shortenUrl(url),
    );
    setState(() => _items.insert(0, item));
    _urlController.clear();
    _enqueue(item);
  }

  void _enqueue(DownloadItem item) {
    if (_activeCount < _maxParallel) {
      _startDownload(item);
    } else {
      _queue.add(item);
    }
  }

  Future<void> _startDownload(DownloadItem item) async {
    if (_ytDlpPath == null || _saveDir == null) return;
    setState(() => _activeCount++);

    try {
      item.status = DownloadStatus.fetching;
      _update();

      final output = '$_saveDir/%(title)s.%(ext)s';
      final args = [
        '--no-check-certificates',
        '-x',
        '--audio-format', 'mp3',
        '--audio-quality', '0',
        '--embed-thumbnail',
        '--add-metadata',
        '--newline',
        '-o', output,
        item.url,
      ];

      final process = await Process.start(_ytDlpPath!, args);
      item.status = DownloadStatus.downloading;
      _update();

      // stdout 파싱
      process.stdout
          .transform(const SystemEncoding().decoder)
          .listen((line) {
        // 진행률
        final pctMatch = RegExp(r'([\d.]+)%').firstMatch(line);
        if (pctMatch != null) {
          item.progress = (double.tryParse(pctMatch.group(1)!) ?? 0) / 100;
        }
        // 속도
        final spdMatch = RegExp(r'at\s+([\S]+/s)').firstMatch(line);
        if (spdMatch != null) item.speedLabel = spdMatch.group(1)!;

        // 완성 파일 경로
        final destMatch = RegExp(r'Destination:\s+(.+\.mp3)').firstMatch(line);
        if (destMatch != null) {
          item.filePath = destMatch.group(1)!;
          item.title = item.filePath!.split('/').last.replaceAll('.mp3', '');
        }
        _update();
      });

      // stderr 수집
      final errBuf = StringBuffer();
      process.stderr
          .transform(const SystemEncoding().decoder)
          .listen(errBuf.write);

      final code = await process.exitCode;
      if (code == 0) {
        item.status = DownloadStatus.done;
        item.progress = 1.0;
        item.speedLabel = '';
      } else {
        item.status = DownloadStatus.error;
        item.errorMsg = _cleanError(errBuf.toString());
      }
    } catch (e) {
      item.status = DownloadStatus.error;
      item.errorMsg = e.toString();
    }

    setState(() => _activeCount--);
    _update();

    // 큐에서 다음 항목 시작
    if (_queue.isNotEmpty) {
      _startDownload(_queue.removeAt(0));
    }
  }

  void _update() => setState(() {});

  void _removeItem(String id) {
    setState(() => _items.removeWhere((e) => e.id == id));
  }

  void _clearDone() {
    setState(() => _items.removeWhere(
        (e) => e.status == DownloadStatus.done || e.status == DownloadStatus.error));
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _urlController.text = data!.text!;
    }
  }

  String _shortenUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host + uri.path.substring(0, uri.path.length.clamp(0, 30));
    } catch (_) {
      return url.length > 50 ? '${url.substring(0, 50)}...' : url;
    }
  }

  String _cleanError(String raw) {
    for (final l in raw.split('\n')) {
      if (l.contains('ERROR:')) {
        return l.replaceFirst(RegExp(r'.*ERROR:\s*'), '');
      }
    }
    return raw.length > 100 ? '${raw.substring(0, 100)}...' : raw;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final waiting = _queue.length;
    final done = _items.where((e) => e.status == DownloadStatus.done).length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── 헤더 ──────────────────────────────────
            _Header(
              activeCount: _activeCount,
              waitingCount: waiting,
              doneCount: done,
            ),

            // ── URL 입력 ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        style: TextStyle(color: cs.onSurface, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'YouTube / Vimeo URL 붙여넣기',
                          hintStyle: TextStyle(
                              color: cs.onSurface.withOpacity(0.35), fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _addUrl(),
                        textInputAction: TextInputAction.go,
                      ),
                    ),
                    // 붙여넣기 버튼
                    GestureDetector(
                      onTap: _pasteFromClipboard,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.content_paste_rounded,
                            color: cs.primary, size: 20),
                      ),
                    ),
                    // 추가 버튼
                    GestureDetector(
                      onTap: _ready ? _addUrl : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [cs.primary, cs.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '추가',
                          style: TextStyle(
                              color: cs.onPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── 상태 바 ───────────────────────────────
            if (_items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '${_items.length}개  •  진행 $_activeCount  •  대기 $waiting',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
                    ),
                    const Spacer(),
                    if (done > 0)
                      GestureDetector(
                        onTap: _clearDone,
                        child: Text(
                          '완료 항목 지우기',
                          style: TextStyle(fontSize: 12, color: cs.primary),
                        ),
                      ),
                  ],
                ),
              ),

            // ── 다운로드 목록 ─────────────────────────
            Expanded(
              child: _items.isEmpty
                  ? _EmptyState(ready: _ready)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: _items.length,
                      itemBuilder: (ctx, i) {
                        final item = _items[i];
                        return DownloadCard(
                          key: ValueKey(item.id),
                          item: item,
                          onRemove: () => _removeItem(item.id),
                          onOpen: item.filePath != null
                              ? () => OpenFilex.open(item.filePath!)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 헤더 위젯 ─────────────────────────────────────────
class _Header extends StatelessWidget {
  final int activeCount, waitingCount, doneCount;
  const _Header({
    required this.activeCount,
    required this.waitingCount,
    required this.doneCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          const AppIconWidget(size: 36),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MP3 Downloader',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      letterSpacing: -0.3)),
              Text('최대 3개 동시 다운로드',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withOpacity(0.4))),
            ],
          ),
          const Spacer(),
          if (activeCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                SizedBox(
                  width: 10, height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Text('$activeCount개 진행 중',
                    style: TextStyle(fontSize: 11, color: cs.primary)),
              ]),
            ),
        ],
      ),
    );
  }
}

// ── 빈 상태 ───────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool ready;
  const _EmptyState({required this.ready});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_note_rounded,
              size: 56, color: cs.onSurface.withOpacity(0.15)),
          const SizedBox(height: 16),
          Text(
            ready ? 'URL을 입력하면\nMP3로 다운로드돼요' : '준비 중...',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15,
                color: cs.onSurface.withOpacity(0.35),
                height: 1.6),
          ),
        ],
      ),
    );
  }
}
