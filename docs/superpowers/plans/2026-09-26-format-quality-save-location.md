# 다운로드 형식/화질 선택 및 저장 위치 설정 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 모바일 앱(`mobile/`)에서 사용자가 다운로드 형식(mp3/mp4)과 화질을 드롭다운으로
선택하고, 저장 위치를 직접 지정할 수 있게 한다.

**Architecture:** 순수 값 모델(형식/화질 enum)과 설정 영속화(shared_preferences)를
UI에서 쉽게 재사용 가능한 작은 위젯으로 분리하고, `DownloadService`의 다운로드
파이프라인을 "스트림 다운로드 → ffmpeg 인코딩/먹싱 → SAF로 저장" 3단계로
재구성한다. 화질 선택 로직과 ffmpeg 명령 생성은 순수 함수로 분리해 유닛 테스트로
검증하고, 네이티브 실행(ffmpeg)과 SAF 파일 쓰기는 `DownloadService`에 주입 가능한
함수 타입으로 감싸 오케스트레이션 로직을 테스트 가능하게 만든다.

**Tech Stack:** Flutter/Dart, `youtube_explode_dart`(기존), `ffmpeg_kit_flutter_new`(신규),
`saf`(신규, Android SAF), `shared_preferences`(신규)

**Spec:** `docs/superpowers/specs/2026-09-26-format-quality-save-location-design.md`

## Global Constraints

- mp3 선택 시 원본 코덱을 확장자만 바꿔 저장하지 않고 실제로 mp3로 재인코딩한다.
- ffmpeg 의존성은 `ffmpeg_kit_flutter_new`를 사용한다 (원조 `ffmpeg_kit_flutter`는
  2025년 네이티브 바이너리 배포가 중단되어 사용하지 않는다).
- 저장 위치 지정은 Android SAF(Storage Access Framework) 폴더 선택기로 구현한다.
- 형식/화질 옵션은 URL 입력란 근처의 공통 드롭다운으로 제공하며, 변경 시점 이후에
  새로 추가되는 항목에만 적용한다. 이미 큐에 들어간 항목은 소급 적용하지 않는다
  (선택 당시 값을 `DownloadItem`에 스냅샷으로 저장).
- 요청한 화질의 스트림이 없으면 에러로 처리하지 않고 사용 가능한 화질로 자동
  대체하며, 실제 적용된 화질을 사용자에게 보여준다.
- iOS 지원은 범위 밖이다.

## Review Focus

- 요청 화질(예: 720p)의 스트림이 없어 낮은 화질로 조용히 대체될 때, 사용자가
  실제 적용된 화질을 화면에서 확인할 수 있어야 한다 — Task 3(`qualityLabel`),
  Task 5(`selectVideoStream` fallback 테스트).
- `shared_preferences`에 저장된 값이 깨졌거나(예: enum 이름 불일치) 없을 때
  앱이 크래시하지 않고 기본값으로 동작해야 한다 — Task 4.
- ffmpeg 실행이 비정상 종료 코드를 반환했을 때 빈 파일이나 손상된 파일이 "완료"로
  잘못 표시되지 않고 에러로 처리되어야 한다 — Task 10.
- 저장 위치를 SAF로 지정한 항목은 일반 파일시스템 경로가 없으므로 기존 "열기"
  버튼이 더 이상 노출되지 않는다는 것을 알고 있어야 한다(회귀 아님, 의도된
  동작) — Task 10, Task 11에 명시.
- mp4 다운로드 중 영상/오디오 스트림 중 하나만 실패해도 임시 파일이 남지 않고
  정리되어야 한다 — Task 10 (`try/finally` 정리 로직).

---

## File Structure

| 파일 | 책임 |
|---|---|
| `mobile/pubspec.yaml` | 신규 의존성 3개 추가 |
| `mobile/lib/models/download_options.dart` (신규) | `DownloadFormat`/`AudioQuality`/`VideoQuality` enum과 라벨 |
| `mobile/lib/models/download_item.dart` (수정) | `processing` 상태, 형식/화질 스냅샷 필드, `qualityLabel` |
| `mobile/lib/services/settings_service.dart` (신규) | `AppSettings` 모델 + `shared_preferences` 영속화 |
| `mobile/lib/services/stream_selection.dart` (신규) | 화질 자동 대체를 포함한 영상 스트림 선택 순수 함수 |
| `mobile/lib/services/ffmpeg_commands.dart` (신규) | mp3 인코딩 / mp4 먹싱 ffmpeg 인자 생성 순수 함수 |
| `mobile/lib/widgets/download_card.dart` (수정) | `processing` 상태 아이콘/색상/진행 표시 |
| `mobile/lib/widgets/format_quality_selector.dart` (신규) | 형식/화질 드롭다운 프레젠테이션 위젯 |
| `mobile/lib/widgets/save_location_bar.dart` (신규) | 저장 위치 표시 + 변경 버튼 프레젠테이션 위젯 |
| `mobile/lib/services/download_service.dart` (수정) | 다운로드→인코딩/먹싱→SAF 저장 파이프라인 재구성 |
| `mobile/lib/screens/home_screen.dart` (수정) | 새 위젯/설정 서비스 연결 |
| `mobile/android/app/build.gradle.kts` (수정) | ffmpeg 네이티브 라이브러리로 인한 APK 용량 증가 완화용 `abiFilters` |

---

### Task 1: 신규 의존성 추가

**Files:**
- Modify: `mobile/pubspec.yaml:9-24`

**Interfaces:**
- Produces: `ffmpeg_kit_flutter_new`, `saf`, `shared_preferences` 패키지를 이후 모든
  태스크에서 import 가능

- [ ] **Step 1: pubspec.yaml에 의존성 추가**

`mobile/pubspec.yaml`의 `dependencies:` 블록에서 `youtube_explode_dart: ^3.1.0` 줄
바로 아래에 추가:

```yaml
  youtube_explode_dart: ^3.1.0
  # 오디오 인코딩(mp3) / 영상+오디오 먹싱(mp4)
  ffmpeg_kit_flutter_new: ^3.2.0
  # 저장 위치 선택 (Android SAF)
  saf: ^2.1.0
  # 형식/화질/저장 위치 설정 영속화
  shared_preferences: ^2.3.0
```

- [ ] **Step 2: 의존성 설치**

Run: `cd mobile && flutter pub get`
Expected: 오류 없이 종료, `mobile/pubspec.lock`이 갱신됨. 버전 충돌이 발생하면
`flutter pub get`이 제안하는 호환 버전으로 caret 제약을 조정한다.

- [ ] **Step 3: Commit**

```bash
git add mobile/pubspec.yaml mobile/pubspec.lock
git commit -m "$(cat <<'EOF'
Add ffmpeg_kit_flutter_new, saf, shared_preferences dependencies

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FALh39LeqgwvbYuZkDnMUo
EOF
)"
```

---

### Task 2: 형식/화질 enum 모델

**Files:**
- Create: `mobile/lib/models/download_options.dart`
- Test: `mobile/test/models/download_options_test.dart`

**Interfaces:**
- Produces:
  - `enum DownloadFormat { mp3, mp4 }` with `.label` getter (String)
  - `enum AudioQuality { kbps128, kbps192, kbps320 }` with `.bitrateKbps` (int), `.label` (String)
  - `enum VideoQuality { q360p, q480p, q720p, q1080p }` with `.heightPx` (int), `.label` (String)
  - `const AudioQuality defaultAudioQuality`, `const VideoQuality defaultVideoQuality`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/models/download_options_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/models/download_options.dart';

void main() {
  test('DownloadFormat labels', () {
    expect(DownloadFormat.mp3.label, 'MP3 (오디오)');
    expect(DownloadFormat.mp4.label, 'MP4 (영상)');
  });

  test('AudioQuality bitrate and label', () {
    expect(AudioQuality.kbps128.bitrateKbps, 128);
    expect(AudioQuality.kbps192.bitrateKbps, 192);
    expect(AudioQuality.kbps320.bitrateKbps, 320);
    expect(AudioQuality.kbps192.label, '192 kbps');
  });

  test('VideoQuality height and label', () {
    expect(VideoQuality.q360p.heightPx, 360);
    expect(VideoQuality.q480p.heightPx, 480);
    expect(VideoQuality.q720p.heightPx, 720);
    expect(VideoQuality.q1080p.heightPx, 1080);
    expect(VideoQuality.q720p.label, '720p');
  });

  test('defaults', () {
    expect(defaultAudioQuality, AudioQuality.kbps192);
    expect(defaultVideoQuality, VideoQuality.q720p);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/models/download_options_test.dart`
Expected: FAIL — `download_options.dart`가 존재하지 않아 import 에러.

- [ ] **Step 3: Write the implementation**

Create `mobile/lib/models/download_options.dart`:

```dart
enum DownloadFormat { mp3, mp4 }

enum AudioQuality { kbps128, kbps192, kbps320 }

enum VideoQuality { q360p, q480p, q720p, q1080p }

extension DownloadFormatLabel on DownloadFormat {
  String get label {
    switch (this) {
      case DownloadFormat.mp3:
        return 'MP3 (오디오)';
      case DownloadFormat.mp4:
        return 'MP4 (영상)';
    }
  }
}

extension AudioQualityLabel on AudioQuality {
  int get bitrateKbps {
    switch (this) {
      case AudioQuality.kbps128:
        return 128;
      case AudioQuality.kbps192:
        return 192;
      case AudioQuality.kbps320:
        return 320;
    }
  }

  String get label => '$bitrateKbps kbps';
}

extension VideoQualityLabel on VideoQuality {
  int get heightPx {
    switch (this) {
      case VideoQuality.q360p:
        return 360;
      case VideoQuality.q480p:
        return 480;
      case VideoQuality.q720p:
        return 720;
      case VideoQuality.q1080p:
        return 1080;
    }
  }

  String get label => '${heightPx}p';
}

const defaultAudioQuality = AudioQuality.kbps192;
const defaultVideoQuality = VideoQuality.q720p;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/models/download_options_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/models/download_options.dart mobile/test/models/download_options_test.dart
git commit -m "$(cat <<'EOF'
Add DownloadFormat/AudioQuality/VideoQuality option models

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FALh39LeqgwvbYuZkDnMUo
EOF
)"
```

---

### Task 3: `DownloadItem` / `DownloadStatus`에 형식·화질·processing 상태 추가

**Files:**
- Modify: `mobile/lib/models/download_item.dart` (전체 재작성)
- Test: `mobile/test/models/download_item_test.dart`

**Interfaces:**
- Consumes: Task 2의 `DownloadFormat`, `AudioQuality`, `VideoQuality`
- Produces:
  - `enum DownloadStatus { waiting, fetching, downloading, processing, done, error }`
  - `DownloadItem({required id, required url, required format, audioQuality, videoQuality, title, status, progress, errorMsg, filePath, speedLabel, appliedHeightPx})`
    — `format == mp3`이면 `audioQuality`는 필수·`videoQuality`는 null, `format == mp4`이면
    반대 (assert로 검증)
  - `DownloadItem.appliedHeightPx` (int?, nullable, mp4 화질 자동 대체 결과 기록용)
  - `DownloadItem.qualityLabel` getter (String)
  - `DownloadItem.isActive`에 `processing` 포함

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/models/download_item_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/models/download_item.dart';
import 'package:yt_downloader/models/download_options.dart';

void main() {
  test('statusLabel covers processing', () {
    final item = DownloadItem(
      id: '1',
      url: 'https://example.com',
      format: DownloadFormat.mp3,
      audioQuality: AudioQuality.kbps192,
      status: DownloadStatus.processing,
    );
    expect(item.statusLabel, '변환 중');
  });

  test('isActive is true while processing', () {
    final item = DownloadItem(
      id: '1',
      url: 'https://example.com',
      format: DownloadFormat.mp3,
      audioQuality: AudioQuality.kbps192,
      status: DownloadStatus.processing,
    );
    expect(item.isActive, isTrue);
  });

  test('qualityLabel for mp3 shows audio bitrate', () {
    final item = DownloadItem(
      id: '1',
      url: 'https://example.com',
      format: DownloadFormat.mp3,
      audioQuality: AudioQuality.kbps320,
    );
    expect(item.qualityLabel, '320 kbps');
  });

  test('qualityLabel for mp4 without fallback shows requested height', () {
    final item = DownloadItem(
      id: '1',
      url: 'https://example.com',
      format: DownloadFormat.mp4,
      videoQuality: VideoQuality.q720p,
      appliedHeightPx: 720,
    );
    expect(item.qualityLabel, '720p');
  });

  test('qualityLabel for mp4 with fallback shows requested-to-applied text', () {
    final item = DownloadItem(
      id: '1',
      url: 'https://example.com',
      format: DownloadFormat.mp4,
      videoQuality: VideoQuality.q720p,
      appliedHeightPx: 480,
    );
    expect(item.qualityLabel, '720p 요청 → 480p로 다운로드됨');
  });

  test('constructor asserts format matches exactly one quality', () {
    expect(
      () => DownloadItem(
        id: '1',
        url: 'https://example.com',
        format: DownloadFormat.mp3,
        videoQuality: VideoQuality.q720p,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/models/download_item_test.dart`
Expected: FAIL — 현재 `DownloadItem` 생성자에 `format` 파라미터가 없어 컴파일 에러.

- [ ] **Step 3: Write the implementation**

Replace the entire content of `mobile/lib/models/download_item.dart`:

```dart
import 'download_options.dart';

enum DownloadStatus { waiting, fetching, downloading, processing, done, error }

class DownloadItem {
  final String id;
  final String url;
  String title;
  DownloadStatus status;
  double progress;   // 0.0 ~ 1.0
  String? errorMsg;
  String? filePath;
  String speedLabel;

  final DownloadFormat format;
  final AudioQuality? audioQuality;
  final VideoQuality? videoQuality;
  int? appliedHeightPx;

  DownloadItem({
    required this.id,
    required this.url,
    required this.format,
    this.audioQuality,
    this.videoQuality,
    this.title = '',
    this.status = DownloadStatus.waiting,
    this.progress = 0,
    this.errorMsg,
    this.filePath,
    this.speedLabel = '',
    this.appliedHeightPx,
  }) : assert(
          (format == DownloadFormat.mp3 &&
                  audioQuality != null &&
                  videoQuality == null) ||
              (format == DownloadFormat.mp4 &&
                  videoQuality != null &&
                  audioQuality == null),
          'format must be paired with exactly one matching quality value',
        );

  String get statusLabel {
    switch (status) {
      case DownloadStatus.waiting:     return '대기 중';
      case DownloadStatus.fetching:    return '정보 수집 중';
      case DownloadStatus.downloading: return '다운로드 중';
      case DownloadStatus.processing:  return '변환 중';
      case DownloadStatus.done:        return '완료';
      case DownloadStatus.error:       return errorMsg ?? '오류';
    }
  }

  String get qualityLabel {
    if (format == DownloadFormat.mp3) return audioQuality!.label;
    final requestedHeight = videoQuality!.heightPx;
    final appliedHeight = appliedHeightPx ?? requestedHeight;
    if (appliedHeight != requestedHeight) {
      return '${requestedHeight}p 요청 → ${appliedHeight}p로 다운로드됨';
    }
    return '${appliedHeight}p';
  }

  bool get isActive =>
      status == DownloadStatus.fetching ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.processing;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/models/download_item_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/models/download_item.dart mobile/test/models/download_item_test.dart
git commit -m "$(cat <<'EOF'
Add processing status and format/quality snapshot to DownloadItem

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FALh39LeqgwvbYuZkDnMUo
EOF
)"
```

---

### Task 4: 설정 영속화 (`AppSettings` / `SettingsService`)

**Files:**
- Create: `mobile/lib/services/settings_service.dart`
- Test: `mobile/test/services/settings_service_test.dart`

**Interfaces:**
- Consumes: Task 2의 `DownloadFormat`, `AudioQuality`, `VideoQuality`
- Produces:
  - `class AppSettings { final DownloadFormat format; final AudioQuality audioQuality; final VideoQuality videoQuality; final String? saveDirUri; }`
    with `const AppSettings.defaults` and `AppSettings copyWith({...})`
  - `class SettingsService { Future<AppSettings> load(); Future<void> save(AppSettings settings); }`

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/services/settings_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yt_downloader/models/download_options.dart';
import 'package:yt_downloader/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load returns defaults when nothing stored', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService().load();
    expect(settings.format, AppSettings.defaults.format);
    expect(settings.audioQuality, AppSettings.defaults.audioQuality);
    expect(settings.videoQuality, AppSettings.defaults.videoQuality);
    expect(settings.saveDirUri, isNull);
  });

  test('save then load round-trips values', () async {
    SharedPreferences.setMockInitialValues({});
    final service = SettingsService();
    await service.save(const AppSettings(
      format: DownloadFormat.mp4,
      audioQuality: AudioQuality.kbps320,
      videoQuality: VideoQuality.q1080p,
      saveDirUri: 'content://tree/abc',
    ));

    final loaded = await service.load();
    expect(loaded.format, DownloadFormat.mp4);
    expect(loaded.audioQuality, AudioQuality.kbps320);
    expect(loaded.videoQuality, VideoQuality.q1080p);
    expect(loaded.saveDirUri, 'content://tree/abc');
  });

  test('load falls back to defaults when stored enum name is invalid', () async {
    SharedPreferences.setMockInitialValues({
      'download_format': 'not_a_real_format',
    });
    final settings = await SettingsService().load();
    expect(settings.format, AppSettings.defaults.format);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/services/settings_service_test.dart`
Expected: FAIL — `settings_service.dart`가 존재하지 않아 import 에러.

- [ ] **Step 3: Write the implementation**

Create `mobile/lib/services/settings_service.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_options.dart';

class AppSettings {
  final DownloadFormat format;
  final AudioQuality audioQuality;
  final VideoQuality videoQuality;
  final String? saveDirUri;

  const AppSettings({
    required this.format,
    required this.audioQuality,
    required this.videoQuality,
    this.saveDirUri,
  });

  static const defaults = AppSettings(
    format: DownloadFormat.mp3,
    audioQuality: defaultAudioQuality,
    videoQuality: defaultVideoQuality,
    saveDirUri: null,
  );

  AppSettings copyWith({
    DownloadFormat? format,
    AudioQuality? audioQuality,
    VideoQuality? videoQuality,
    String? saveDirUri,
  }) {
    return AppSettings(
      format: format ?? this.format,
      audioQuality: audioQuality ?? this.audioQuality,
      videoQuality: videoQuality ?? this.videoQuality,
      saveDirUri: saveDirUri ?? this.saveDirUri,
    );
  }
}

class SettingsService {
  static const _keyFormat = 'download_format';
  static const _keyAudioQuality = 'audio_quality';
  static const _keyVideoQuality = 'video_quality';
  static const _keySaveDirUri = 'save_dir_uri';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      format: _readEnum(prefs, _keyFormat, DownloadFormat.values) ??
          AppSettings.defaults.format,
      audioQuality: _readEnum(prefs, _keyAudioQuality, AudioQuality.values) ??
          AppSettings.defaults.audioQuality,
      videoQuality: _readEnum(prefs, _keyVideoQuality, VideoQuality.values) ??
          AppSettings.defaults.videoQuality,
      saveDirUri: prefs.getString(_keySaveDirUri),
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFormat, settings.format.name);
    await prefs.setString(_keyAudioQuality, settings.audioQuality.name);
    await prefs.setString(_keyVideoQuality, settings.videoQuality.name);
    if (settings.saveDirUri != null) {
      await prefs.setString(_keySaveDirUri, settings.saveDirUri!);
    } else {
      await prefs.remove(_keySaveDirUri);
    }
  }

  T? _readEnum<T extends Enum>(SharedPreferences prefs, String key, List<T> values) {
    final raw = prefs.getString(key);
    if (raw == null) return null;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/services/settings_service_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/services/settings_service.dart mobile/test/services/settings_service_test.dart
git commit -m "$(cat <<'EOF'
Add AppSettings persistence via shared_preferences

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FALh39LeqgwvbYuZkDnMUo
EOF
)"
```

---

### Task 5: 영상 화질 자동 대체 선택 로직 (순수 함수)

**Files:**
- Create: `mobile/lib/services/stream_selection.dart`
- Test: `mobile/test/services/stream_selection_test.dart`

**Interfaces:**
- Produces:
  - `class VideoStreamCandidate { final int heightPx; final int bitrateBitsPerSecond; }`
  - `class VideoStreamSelectionResult { final int candidateIndex; final int appliedHeightPx; }`
  - `VideoStreamSelectionResult? selectVideoStream(List<VideoStreamCandidate> candidates, int requestedHeightPx)`

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/services/stream_selection_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/services/stream_selection.dart';

void main() {
  test('returns null for empty candidate list', () {
    expect(selectVideoStream([], 720), isNull);
  });

  test('picks exact height match', () {
    final candidates = [
      VideoStreamCandidate(heightPx: 360, bitrateBitsPerSecond: 500000),
      VideoStreamCandidate(heightPx: 720, bitrateBitsPerSecond: 2000000),
    ];
    final result = selectVideoStream(candidates, 720);
    expect(result!.candidateIndex, 1);
    expect(result.appliedHeightPx, 720);
  });

  test('falls back to highest height at or below requested when exact match missing', () {
    final candidates = [
      VideoStreamCandidate(heightPx: 360, bitrateBitsPerSecond: 500000),
      VideoStreamCandidate(heightPx: 480, bitrateBitsPerSecond: 900000),
      VideoStreamCandidate(heightPx: 1080, bitrateBitsPerSecond: 5000000),
    ];
    final result = selectVideoStream(candidates, 720);
    expect(result!.candidateIndex, 1);
    expect(result.appliedHeightPx, 480);
  });

  test('falls back to lowest available height when all candidates exceed requested', () {
    final candidates = [
      VideoStreamCandidate(heightPx: 720, bitrateBitsPerSecond: 2000000),
      VideoStreamCandidate(heightPx: 1080, bitrateBitsPerSecond: 5000000),
    ];
    final result = selectVideoStream(candidates, 360);
    expect(result!.candidateIndex, 0);
    expect(result.appliedHeightPx, 720);
  });

  test('picks highest bitrate among candidates that share the chosen height', () {
    final candidates = [
      VideoStreamCandidate(heightPx: 720, bitrateBitsPerSecond: 1500000),
      VideoStreamCandidate(heightPx: 720, bitrateBitsPerSecond: 2500000),
    ];
    final result = selectVideoStream(candidates, 720);
    expect(result!.candidateIndex, 1);
    expect(result.appliedHeightPx, 720);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/services/stream_selection_test.dart`
Expected: FAIL — `stream_selection.dart`가 존재하지 않아 import 에러.

- [ ] **Step 3: Write the implementation**

Create `mobile/lib/services/stream_selection.dart`:

```dart
class VideoStreamCandidate {
  final int heightPx;
  final int bitrateBitsPerSecond;

  const VideoStreamCandidate({
    required this.heightPx,
    required this.bitrateBitsPerSecond,
  });
}

class VideoStreamSelectionResult {
  final int candidateIndex;
  final int appliedHeightPx;

  const VideoStreamSelectionResult({
    required this.candidateIndex,
    required this.appliedHeightPx,
  });
}

/// 요청 화질 이하 중 가장 높은 화질을 우선 선택한다. 요청 화질 이하가 하나도
/// 없으면(모든 후보가 요청보다 고화질인 경우) 사용 가능한 가장 낮은 화질로
/// 대체한다. 같은 높이의 후보가 여러 개면 비트레이트가 가장 높은 것을 고른다.
VideoStreamSelectionResult? selectVideoStream(
  List<VideoStreamCandidate> candidates,
  int requestedHeightPx,
) {
  if (candidates.isEmpty) return null;

  final atOrBelow = <int>[
    for (var i = 0; i < candidates.length; i++)
      if (candidates[i].heightPx <= requestedHeightPx) i,
  ];

  final pool = atOrBelow.isNotEmpty
      ? atOrBelow
      : List.generate(candidates.length, (i) => i);

  final heights = pool.map((i) => candidates[i].heightPx);
  final targetHeight =
      atOrBelow.isNotEmpty ? heights.reduce((a, b) => a > b ? a : b) : heights.reduce((a, b) => a < b ? a : b);

  final sameHeight = pool.where((i) => candidates[i].heightPx == targetHeight).toList()
    ..sort((a, b) =>
        candidates[b].bitrateBitsPerSecond.compareTo(candidates[a].bitrateBitsPerSecond));

  final chosen = sameHeight.first;
  return VideoStreamSelectionResult(
    candidateIndex: chosen,
    appliedHeightPx: candidates[chosen].heightPx,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/services/stream_selection_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/services/stream_selection.dart mobile/test/services/stream_selection_test.dart
git commit -m "$(cat <<'EOF'
Add pure video stream quality-fallback selection logic

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FALh39LeqgwvbYuZkDnMUo
EOF
)"
```

---

### Task 6: ffmpeg 명령 인자 생성 (순수 함수)

**Files:**
- Create: `mobile/lib/services/ffmpeg_commands.dart`
- Test: `mobile/test/services/ffmpeg_commands_test.dart`

**Interfaces:**
- Produces:
  - `List<String> buildMp3EncodeArgs({required String audioInputPath, required String outputPath, required int bitrateKbps})`
  - `List<String> buildMp4MuxArgs({required String videoInputPath, required String audioInputPath, required String outputPath})`

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/services/ffmpeg_commands_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/services/ffmpeg_commands.dart';

void main() {
  test('buildMp3EncodeArgs sets bitrate and strips video', () {
    final args = buildMp3EncodeArgs(
      audioInputPath: '/tmp/audio.m4a',
      outputPath: '/tmp/out.mp3',
      bitrateKbps: 192,
    );
    expect(args, [
      '-y',
      '-i', '/tmp/audio.m4a',
      '-vn',
      '-b:a', '192k',
      '/tmp/out.mp3',
    ]);
  });

  test('buildMp4MuxArgs copies video and transcodes audio to aac', () {
    final args = buildMp4MuxArgs(
      videoInputPath: '/tmp/video.mp4',
      audioInputPath: '/tmp/audio.m4a',
      outputPath: '/tmp/out.mp4',
    );
    expect(args, [
      '-y',
      '-i', '/tmp/video.mp4',
      '-i', '/tmp/audio.m4a',
      '-c:v', 'copy',
      '-c:a', 'aac',
      '/tmp/out.mp4',
    ]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/services/ffmpeg_commands_test.dart`
Expected: FAIL — `ffmpeg_commands.dart`가 존재하지 않아 import 에러.

- [ ] **Step 3: Write the implementation**

Create `mobile/lib/services/ffmpeg_commands.dart`:

```dart
/// `-y`는 임시 파일명이 우연히 겹칠 때 ffmpeg가 대화형 덮어쓰기 확인으로
/// 멈추는 것을 막기 위해 항상 포함한다.
List<String> buildMp3EncodeArgs({
  required String audioInputPath,
  required String outputPath,
  required int bitrateKbps,
}) {
  return [
    '-y',
    '-i', audioInputPath,
    '-vn',
    '-b:a', '${bitrateKbps}k',
    outputPath,
  ];
}

List<String> buildMp4MuxArgs({
  required String videoInputPath,
  required String audioInputPath,
  required String outputPath,
}) {
  return [
    '-y',
    '-i', videoInputPath,
    '-i', audioInputPath,
    '-c:v', 'copy',
    '-c:a', 'aac',
    outputPath,
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/services/ffmpeg_commands_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/services/ffmpeg_commands.dart mobile/test/services/ffmpeg_commands_test.dart
git commit -m "$(cat <<'EOF'
Add pure ffmpeg argument builders for mp3 encode and mp4 mux

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FALh39LeqgwvbYuZkDnMUo
EOF
)"
```

---

### Task 7: `DownloadCard`에 `processing` 상태 UI 추가

**Files:**
- Modify: `mobile/lib/widgets/download_card.dart`
- Test: `mobile/test/widgets/download_card_test.dart`

**Interfaces:**
- Consumes: Task 3의 `DownloadStatus.processing`, `DownloadItem.statusLabel` ('변환 중')

- [ ] **Step 1: Write the failing test**

Create `mobile/test/widgets/download_card_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/widgets/download_card_test.dart`
Expected: FAIL — `processing` 상태에 대한 case가 없어 switch 문에서
"no case for" 관련 컴파일 에러(비-exhaustive switch) 발생.

- [ ] **Step 3: Write the implementation**

In `mobile/lib/widgets/download_card.dart`, update the four `switch (item.status)`
blocks:

Progress bar condition (around line 118-119):

```dart
          if (item.status == DownloadStatus.downloading ||
              item.status == DownloadStatus.fetching ||
              item.status == DownloadStatus.processing)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: item.status == DownloadStatus.downloading
                      ? item.progress
                      : null,
                  minHeight: 3,
                  backgroundColor: cs.onSurface.withOpacity(0.08),
                  valueColor: AlwaysStoppedAnimation(
                    item.status == DownloadStatus.downloading
                        ? cs.primary
                        : cs.secondary,
                  ),
                ),
              ),
            )
```

`_iconBg`:

```dart
  Color _iconBg(ColorScheme cs) {
    switch (item.status) {
      case DownloadStatus.waiting:     return cs.onSurface.withOpacity(0.06);
      case DownloadStatus.fetching:    return cs.secondary.withOpacity(0.12);
      case DownloadStatus.downloading: return cs.primary.withOpacity(0.12);
      case DownloadStatus.processing:  return cs.secondary.withOpacity(0.12);
      case DownloadStatus.done:        return cs.secondary.withOpacity(0.15);
      case DownloadStatus.error:       return cs.error.withOpacity(0.12);
    }
  }
```

`_statusColor`:

```dart
  Color _statusColor(ColorScheme cs) {
    switch (item.status) {
      case DownloadStatus.waiting:     return cs.onSurface.withOpacity(0.4);
      case DownloadStatus.fetching:    return cs.secondary;
      case DownloadStatus.downloading: return cs.primary;
      case DownloadStatus.processing:  return cs.secondary;
      case DownloadStatus.done:        return cs.secondary;
      case DownloadStatus.error:       return cs.error;
    }
  }
```

`_statusIcon`:

```dart
  Widget _statusIcon(ColorScheme cs) {
    switch (item.status) {
      case DownloadStatus.waiting:
        return Icon(Icons.schedule_rounded,
            size: 18, color: cs.onSurface.withOpacity(0.4));
      case DownloadStatus.fetching:
        return SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: cs.secondary),
        );
      case DownloadStatus.downloading:
        return Icon(Icons.downloading_rounded, size: 18, color: cs.primary);
      case DownloadStatus.processing:
        return SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: cs.secondary),
        );
      case DownloadStatus.done:
        return Icon(Icons.check_rounded, size: 18, color: cs.secondary);
      case DownloadStatus.error:
        return Icon(Icons.error_outline_rounded, size: 18, color: cs.error);
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/widgets/download_card_test.dart`
Expected: PASS (1 test)

- [ ] **Step 5: Run the full existing widget test suite to check for regressions**

Run: `cd mobile && flutter test test/widget_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/widgets/download_card.dart mobile/test/widgets/download_card_test.dart
git commit -m "$(cat <<'EOF'
Add processing status UI to DownloadCard

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FALh39LeqgwvbYuZkDnMUo
EOF
)"
```

---

### Task 8: `FormatQualitySelector` 위젯

**Files:**
- Create: `mobile/lib/widgets/format_quality_selector.dart`
- Test: `mobile/test/widgets/format_quality_selector_test.dart`

**Interfaces:**
- Consumes: Task 2의 `DownloadFormat`, `AudioQuality`, `VideoQuality`
- Produces: `FormatQualitySelector({format, audioQuality, videoQuality, onFormatChanged, onAudioQualityChanged, onVideoQualityChanged})`

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/widgets/format_quality_selector_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/widgets/format_quality_selector_test.dart`
Expected: FAIL — `format_quality_selector.dart`가 존재하지 않아 import 에러.

- [ ] **Step 3: Write the implementation**

Create `mobile/lib/widgets/format_quality_selector.dart`:

```dart
import 'package:flutter/material.dart';
import '../models/download_options.dart';

class FormatQualitySelector extends StatelessWidget {
  final DownloadFormat format;
  final AudioQuality audioQuality;
  final VideoQuality videoQuality;
  final ValueChanged<DownloadFormat> onFormatChanged;
  final ValueChanged<AudioQuality> onAudioQualityChanged;
  final ValueChanged<VideoQuality> onVideoQualityChanged;

  const FormatQualitySelector({
    super.key,
    required this.format,
    required this.audioQuality,
    required this.videoQuality,
    required this.onFormatChanged,
    required this.onAudioQualityChanged,
    required this.onVideoQualityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButton<DownloadFormat>(
            value: format,
            isExpanded: true,
            items: DownloadFormat.values
                .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                .toList(),
            onChanged: (v) {
              if (v != null) onFormatChanged(v);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: format == DownloadFormat.mp3
              ? DropdownButton<AudioQuality>(
                  value: audioQuality,
                  isExpanded: true,
                  items: AudioQuality.values
                      .map((q) => DropdownMenuItem(value: q, child: Text(q.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onAudioQualityChanged(v);
                  },
                )
              : DropdownButton<VideoQuality>(
                  value: videoQuality,
                  isExpanded: true,
                  items: VideoQuality.values
                      .map((q) => DropdownMenuItem(value: q, child: Text(q.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onVideoQualityChanged(v);
                  },
                ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/widgets/format_quality_selector_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/widgets/format_quality_selector.dart mobile/test/widgets/format_quality_selector_test.dart
git commit -m "$(cat <<'EOF'
Add FormatQualitySelector dropdown widget

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FALh39LeqgwvbYuZkDnMUo
EOF
)"
```

---

### Task 9: `SaveLocationBar` 위젯

**Files:**
- Create: `mobile/lib/widgets/save_location_bar.dart`
- Test: `mobile/test/widgets/save_location_bar_test.dart`

**Interfaces:**
- Produces: `SaveLocationBar({required String displayPath, required VoidCallback onChangePressed})`

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/widgets/save_location_bar_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/widgets/save_location_bar_test.dart`
Expected: FAIL — `save_location_bar.dart`가 존재하지 않아 import 에러.

- [ ] **Step 3: Write the implementation**

Create `mobile/lib/widgets/save_location_bar.dart`:

```dart
import 'package:flutter/material.dart';

class SaveLocationBar extends StatelessWidget {
  final String displayPath;
  final VoidCallback onChangePressed;

  const SaveLocationBar({
    super.key,
    required this.displayPath,
    required this.onChangePressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            displayPath,
            style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: onChangePressed,
          child: const Text('변경'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/widgets/save_location_bar_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/widgets/save_location_bar.dart mobile/test/widgets/save_location_bar_test.dart
git commit -m "$(cat <<'EOF'
Add SaveLocationBar widget

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FALh39LeqgwvbYuZkDnMUo
EOF
)"
```

---

### Task 10: `DownloadService` 파이프라인 재구성 (다운로드 → ffmpeg → SAF 저장)

**Files:**
- Modify: `mobile/lib/services/download_service.dart` (전체 재작성)

**Interfaces:**
- Consumes:
  - Task 2: `DownloadFormat`, `AudioQuality.bitrateKbps`, `VideoQuality.heightPx`
  - Task 3: `DownloadItem` (신규 필드들), `DownloadStatus.processing`
  - Task 5: `VideoStreamCandidate`, `selectVideoStream`
  - Task 6: `buildMp3EncodeArgs`, `buildMp4MuxArgs`
- Produces:
  - `typedef FfmpegRunner = Future<int> Function(List<String> args)`
  - `typedef SafFileWriter = Future<void> Function({required String saveDirUri, required String fileName, required String sourceFilePath})`
  - `DownloadService({FfmpegRunner? ffmpegRunner, SafFileWriter? safWriter})`
  - `DownloadService.enqueue({required DownloadItem item, required String fallbackSaveDir, String? saveDirUri, required void Function() onUpdate})`
    — `enqueue`의 `saveDir` 파라미터가 `fallbackSaveDir` + `saveDirUri`(nullable) 2개로
    분리됨 (Task 11에서 사용)

> **자동 테스트 범위에 대한 참고:** 이 태스크는 실제 네트워크(YouTube 스트림 조회),
> 네이티브 ffmpeg 실행, Android SAF 파일 쓰기에 의존한다. 스펙의 "테스트 방침"
> 섹션에 명시된 대로 이 통합 경로는 자동화된 유닛 테스트 대상이 아니며, 실기기에서
> 수동으로 검증한다(Step 3). 대신 순수 로직(스트림 선택, ffmpeg 인자 생성)은 이미
> Task 5·6에서 유닛 테스트로 커버했고, 이 태스크는 그 결과를 올바른 순서로
> 오케스트레이션하는 데 집중한다.

- [ ] **Step 1: Write the implementation**

Replace the entire content of `mobile/lib/services/download_service.dart`:

```dart
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
  // saf 패키지의 정확한 메서드 시그니처는 설치된 버전의
  // https://pub.dev/packages/saf/example 를 기준으로 삼는다. 시그니처가
  // 다르면 인자 순서/이름만 맞추고 로직(디렉토리 URI, 파일명, MIME, 바이트)은
  // 그대로 유지한다.
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
    await sink.flush();
    await sink.close();
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
```

- [ ] **Step 2: 정적 분석으로 컴파일 에러 확인**

Run: `cd mobile && flutter analyze lib/services/download_service.dart`
Expected: `No issues found!`. `ffmpeg_kit_flutter_new`/`saf`/`youtube_explode_dart`의
설치된 버전이 위 코드와 API 이름(`FFmpegKit.executeWithArguments`,
`getReturnCode().getValue()`, `Saf().writeFileBytes(...)`,
`VideoOnlyStreamInfo.videoResolution.height`)이 다르면, 로직은 그대로 두고
해당 호출부만 설치된 버전의 실제 시그니처에 맞게 고친다.

- [ ] **Step 3: 실기기 수동 검증**

에뮬레이터 또는 실기기에서 `cd mobile && flutter run`으로 앱을 실행하고 다음을
확인한다:

1. 저장 위치를 설정하지 않은 상태에서 mp3(192kbps)로 짧은 영상을 하나
   다운로드한다. 상태가 대기 중 → 정보 수집 중 → 다운로드 중 → 변환 중 → 완료
   순서로 전환되는지 확인한다. 완료 후 기본 폴더(Music/MP3Downloader)에서
   파일이 재생되는지, 재생 앱이 표시하는 비트레이트가 192kbps 근처인지 확인한다.
2. mp4(720p)로 같은 영상을 다운로드한다. 완료 후 영상이 재생되고 화질이
   720p(또는 사용 가능한 가장 가까운 값)인지 확인한다.
3. 일부러 존재하지 않을 만큼 낮은/높은 화질 조합을 테스트해, 카드에 "OOOp
   요청 → OOOp로 다운로드됨" 문구가 뜨는지 확인한다 (Task 11에서 저장 위치
   변경 UI가 붙은 후 진행 가능).
4. 다운로드 도중 비행기 모드를 켜서 네트워크를 끊고, 상태가 오류로 바뀌며
   앱 캐시 디렉토리에 임시 파일이 남지 않는지 확인한다(파일 관리자 또는
   `adb shell run-as com.yeinrah.yt_downloader ls cache`).

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/services/download_service.dart
git commit -m "$(cat <<'EOF'
Rebuild download pipeline with ffmpeg encode/mux and SAF save step

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FALh39LeqgwvbYuZkDnMUo
EOF
)"
```

---

### Task 11: `HomeScreen`에 형식/화질/저장 위치 UI 연결

**Files:**
- Modify: `mobile/lib/screens/home_screen.dart`

**Interfaces:**
- Consumes: Task 4(`SettingsService`, `AppSettings`), Task 8(`FormatQualitySelector`),
  Task 9(`SaveLocationBar`), Task 10(`DownloadService.enqueue`의 새 시그니처)

- [ ] **Step 1: imports와 상태 필드 추가**

`mobile/lib/screens/home_screen.dart` 상단 import 블록을 다음으로 교체:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saf/saf.dart';
import 'package:uuid/uuid.dart';
import 'package:open_filex/open_filex.dart';
import '../models/download_item.dart';
import '../models/download_options.dart';
import '../services/download_service.dart';
import '../services/settings_service.dart';
import '../widgets/download_card.dart';
import '../widgets/app_icon_widget.dart';
import '../widgets/format_quality_selector.dart';
import '../widgets/save_location_bar.dart';
```

`_HomeScreenState`의 필드 선언부(`_urlController` 등)에 추가:

```dart
class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController();
  final _items = <DownloadItem>[];
  final _uuid = const Uuid();
  final _downloadService = DownloadService();
  final _settingsService = SettingsService();
  AppSettings _settings = AppSettings.defaults;
  String? _fallbackSaveDir;
  bool _ready = false;
```

- [ ] **Step 2: `_init()`에서 설정 로드**

`_init()` 메서드를 다음으로 교체:

```dart
  Future<void> _init() async {
    // 권한
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();

    // 저장 경로: /sdcard/Music/MP3Downloader (SAF 미지정 시 폴백)
    final ext = await getExternalStorageDirectory();
    _fallbackSaveDir =
        '${ext?.parent.parent.parent.parent.path ?? '/sdcard'}/Music/MP3Downloader';
    await Directory(_fallbackSaveDir!).create(recursive: true);

    _settings = await _settingsService.load();

    setState(() => _ready = true);
  }
```

- [ ] **Step 3: 설정 변경 핸들러 추가 및 `_addUrl()` 갱신**

`_addUrl()` 메서드를 다음으로 교체:

```dart
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
      format: _settings.format,
      audioQuality:
          _settings.format == DownloadFormat.mp3 ? _settings.audioQuality : null,
      videoQuality:
          _settings.format == DownloadFormat.mp4 ? _settings.videoQuality : null,
    );
    setState(() => _items.insert(0, item));
    _urlController.clear();
    _downloadService.enqueue(
      item: item,
      fallbackSaveDir: _fallbackSaveDir!,
      saveDirUri: _settings.saveDirUri,
      onUpdate: _update,
    );
  }
```

바로 아래(`_update()` 메서드 다음)에 새 메서드들을 추가:

```dart
  void _onFormatChanged(DownloadFormat format) {
    setState(() => _settings = _settings.copyWith(format: format));
    _settingsService.save(_settings);
  }

  void _onAudioQualityChanged(AudioQuality quality) {
    setState(() => _settings = _settings.copyWith(audioQuality: quality));
    _settingsService.save(_settings);
  }

  void _onVideoQualityChanged(VideoQuality quality) {
    setState(() => _settings = _settings.copyWith(videoQuality: quality));
    _settingsService.save(_settings);
  }

  Future<void> _changeSaveLocation() async {
    final uri = await Saf().pickDirectory();
    if (uri == null) return;
    setState(() => _settings = _settings.copyWith(saveDirUri: uri));
    await _settingsService.save(_settings);
  }

  String get _saveLocationLabel =>
      _settings.saveDirUri ?? _fallbackSaveDir ?? '';
```

- [ ] **Step 4: build()에 위젯 삽입**

`build()`의 URL 입력 `Padding` 블록(기존 파일 129-190행)과 상태 바 `Padding`
블록(기존 파일 193-214행) 사이에 다음 두 블록을 추가:

```dart
            // ── 형식/화질 선택 ─────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: FormatQualitySelector(
                format: _settings.format,
                audioQuality: _settings.audioQuality,
                videoQuality: _settings.videoQuality,
                onFormatChanged: _onFormatChanged,
                onAudioQualityChanged: _onAudioQualityChanged,
                onVideoQualityChanged: _onVideoQualityChanged,
              ),
            ),

            // ── 저장 위치 ─────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: SaveLocationBar(
                displayPath: _saveLocationLabel,
                onChangePressed: _changeSaveLocation,
              ),
            ),
```

- [ ] **Step 5: 정적 분석**

Run: `cd mobile && flutter analyze lib/screens/home_screen.dart`
Expected: `No issues found!`

- [ ] **Step 6: 실기기 수동 검증**

`cd mobile && flutter run`으로 실행 후 확인:

1. 형식 드롭다운을 mp3 → mp4로 바꾸면 화질 드롭다운이 kbps 목록에서 해상도
   목록으로 즉시 바뀌는지 확인한다.
2. "변경" 버튼을 눌러 폴더를 선택하면 저장 위치 표시가 바뀌고, 앱을 완전히
   종료했다가 다시 켜도 선택한 형식/화질/저장 위치가 유지되는지 확인한다.
3. 저장 위치를 지정한 채로 하나, 지정하지 않은 채로 하나씩 다운로드해 각각
   지정한 폴더 / 기본 폴더(Music/MP3Downloader)에 파일이 생기는지 확인한다.
4. 저장 위치를 SAF로 지정해 받은 항목은 카드에 "열기" 아이콘이 보이지 않는
   것을 확인한다(의도된 동작).

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/screens/home_screen.dart
git commit -m "$(cat <<'EOF'
Wire format/quality selector and save location settings into HomeScreen

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FALh39LeqgwvbYuZkDnMUo
EOF
)"
```

---

### Task 12: Android APK 용량 완화 및 전체 회귀 확인

**Files:**
- Modify: `mobile/android/app/build.gradle.kts:22-31`

**Interfaces:**
- 없음 (빌드 설정 변경 + 최종 수동 검증)

- [ ] **Step 1: abiFilters 추가**

`mobile/android/app/build.gradle.kts`의 `defaultConfig` 블록을 다음으로 교체:

```kotlin
    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.yeinrah.yt_downloader"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ffmpeg_kit_flutter_new의 네이티브 라이브러리가 4개 ABI를 모두 포함하면
        // APK가 크게 커진다. 실사용 안드로이드 기기 대부분을 커버하는
        // armeabi-v7a/arm64-v8a만 남기고 x86 계열은 제외한다.
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }
```

- [ ] **Step 2: 빌드 확인**

Run: `cd mobile && flutter build apk --debug`
Expected: 빌드 성공. 실패하면 에러 메시지에 따라 `ffmpeg_kit_flutter_new`가
지원하는 ABI 목록을 확인해 `abiFilters` 값을 조정한다.

- [ ] **Step 3: 전체 유닛/위젯 테스트 스위트 실행**

Run: `cd mobile && flutter test`
Expected: 모든 테스트 PASS (Task 2~9에서 작성한 테스트 + 기존 `widget_test.dart`).

- [ ] **Step 4: 최종 수동 회귀 체크리스트**

실기기에서 다음을 순서대로 확인한다:

1. mp3 128/192/320kbps 각각 하나씩 다운로드해 완료 후 재생 및 실제 비트레이트
   확인.
2. mp4 360p/720p/1080p 각각 하나씩 다운로드해 완료 후 재생 및 실제 해상도 확인.
3. 동시에 3개 초과로 URL을 추가했을 때 여전히 최대 3개까지만 동시 진행되는지
   확인(`maxParallel` 로직이 새 파이프라인에서도 유지되는지).
4. 완료/오류 항목 지우기, 항목 개별 삭제가 정상 동작하는지 확인.
5. APK 용량이 이전 대비 과도하게(예: 100MB 이상) 늘지 않았는지
   `flutter build apk --debug` 결과물 크기로 확인.

- [ ] **Step 5: Commit**

```bash
git add mobile/android/app/build.gradle.kts
git commit -m "$(cat <<'EOF'
Limit ffmpeg native library ABIs to reduce APK size

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FALh39LeqgwvbYuZkDnMUo
EOF
)"
```
