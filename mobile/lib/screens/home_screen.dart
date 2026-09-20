import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:open_filex/open_filex.dart';
import '../models/download_item.dart';
import '../services/download_service.dart';
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
  final _downloadService = DownloadService();
  String? _saveDir;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _downloadService.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // 권한
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();

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
    _downloadService.enqueue(
      item: item,
      saveDir: _saveDir!,
      onUpdate: _update,
    );
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

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = _items.where((e) => e.isActive).length;
    final waiting = _items
        .where((e) => e.status == DownloadStatus.waiting)
        .length;
    final done = _items.where((e) => e.status == DownloadStatus.done).length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── 헤더 ──────────────────────────────────
            _Header(
              activeCount: active,
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
                      '${_items.length}개  •  진행 $active  •  대기 $waiting',
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
            ready ? 'URL을 입력하면\n오디오 파일로 다운로드돼요' : '준비 중...',
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
