# 형식/화질 선택 및 저장 위치 설정 — 설계 문서

날짜: 2026-09-26
대상: `mobile/` (Flutter, Android)

## 배경 및 목적

현재 앱(`mobile/`)은 YouTube URL을 받아 `youtube_explode_dart`로 오디오 스트림을
원본 코덱(m4a/webm) 그대로 고정 경로(`/sdcard/Music/MP3Downloader`)에 저장한다.
형식/화질 선택지가 없고, 저장 위치도 사용자가 바꿀 수 없다.

이 작업의 목적:
1. 사용자가 다운로드 형식(mp3/mp4)과 화질(오디오 비트레이트 / 영상 해상도)을
   드롭다운으로 선택할 수 있게 한다.
2. 사용자가 저장 위치를 직접 지정할 수 있게 한다.

## 범위

- mp3 선택 시 실제로 mp3로 재인코딩한다 (원본 코덱을 확장자만 바꿔 저장하지 않는다).
- mp4 선택 시 720p/1080p 등 고화질을 지원한다. YouTube의 고화질 스트림은 영상과
  오디오가 분리되어 있으므로 먹싱(합치기)이 필요하다.
- 저장 위치는 Android SAF(Storage Access Framework) 폴더 선택기로 지정한다.
- 형식/화질 옵션은 URL 입력란 근처의 공통 드롭다운으로 제공하며, 이후 새로
  추가되는 항목에 적용된다(이미 큐에 들어간 항목에는 소급 적용하지 않음).

## 범위 밖

- iOS 지원 (현재 프로젝트에 iOS 타겟 없음)
- 항목별(다운로드마다 다른) 형식/화질 오버라이드 UI
- 다운로드 히스토리/재개 기능

## 의존성 변경

`mobile/pubspec.yaml`에 추가:

- **`ffmpeg_kit_flutter_new`** — 원조 `ffmpeg_kit_flutter`는 2025년 4월 네이티브
  바이너리 배포가 중단되며 사실상 은퇴했다. 커뮤니티가 유지보수하는 포크인
  `ffmpeg_kit_flutter_new`(pub.dev)를 사용한다. mp3 재인코딩과 mp4 먹싱에 사용.
- **`saf`** — Android SAF 기반 폴더 선택/쓰기 패키지(pub.dev). `pickDirectory()`로
  사용자가 폴더를 선택하고, 반환된 URI에 대한 영속 권한을 얻어 이후 파일을 쓴다.
- **`shared_preferences`** — 마지막으로 선택한 형식/화질/저장 위치(SAF URI)를
  앱 재실행 후에도 유지하기 위해 사용.

## 데이터 모델

`mobile/lib/models/download_item.dart` 및 신규 파일:

- `DownloadFormat` enum: `mp3`, `mp4`
- `AudioQuality` enum: `kbps128`, `kbps192`, `kbps320`
  - ffmpeg 출력 비트레이트를 직접 지정하므로 원본 오디오 화질과 무관하게
    고정값으로 인코딩한다.
- `VideoQuality` enum: `q360p`, `q480p`, `q720p`, `q1080p`
  - 요청한 화질의 영상 스트림이 없으면 사용 가능한 가장 가까운 낮은 화질로
    자동 대체한다. 이때 에러로 취급하지 않고, 실제 적용된 화질을 사용자에게
    보여준다(예: "720p 요청 → 480p로 다운로드됨").
- `DownloadItem`에 `format`과 `quality`(선택 당시 값의 스냅샷) 필드를 추가한다.
  큐에 들어간 항목은 이후 설정 화면에서 형식/화질이 바뀌어도 영향받지 않는다.
- `DownloadStatus` enum에 `processing` 상태를 추가한다 (다운로드 완료 후
  ffmpeg 인코딩/먹싱 중인 상태). 기존: `waiting, fetching, downloading, done, error`
  → `waiting, fetching, downloading, processing, done, error`.
- 신규 `AppSettings` (또는 유사한 이름): 현재 선택된 형식, 화질, 저장 위치
  (SAF 트리 URI 문자열)를 보관하고 `shared_preferences`로 영속화하는 간단한
  서비스/모델.

## UI 변경 (`mobile/lib/screens/home_screen.dart`)

- URL 입력창 아래(또는 옆)에 형식 드롭다운(mp3/mp4)과 화질 드롭다운을 추가한다.
  화질 드롭다운의 옵션 목록은 선택된 형식에 따라 달라진다(mp3 선택 시
  `AudioQuality` 옵션, mp4 선택 시 `VideoQuality` 옵션).
- 헤더 근처에 현재 저장 위치를 표시하고 "변경" 버튼을 둔다. 버튼을 누르면
  `saf.pickDirectory()`를 호출하고, 선택된 URI를 `AppSettings`에 저장한다.
- 앱 최초 실행 시 저장 위치가 설정되어 있지 않으면 기존과 동일하게 앱 전용
  기본 폴더(`/sdcard/Music/MP3Downloader` 상당)로 폴백한다.
- `mobile/lib/widgets/download_card.dart`에 `processing` 상태에 맞는
  아이콘/라벨("인코딩 중" 등)/비결정형 진행 표시(스피너)를 추가한다.

## 다운로드 파이프라인 (`mobile/lib/services/download_service.dart`)

기존 흐름: 스트림 조회 → 오디오 스트림을 파일로 직접 스트리밍 저장 (재인코딩 없음).

변경 후 흐름:

1. **fetching**: 매니페스트 조회.
   - mp3: 오디오 전용 스트림 중 하나를 선택(기존 로직 재사용 가능).
   - mp4: 요청 화질에 해당하는 video-only 스트림 + 가장 좋은 오디오 전용
     스트림을 선택한다(1080p까지는 대부분 분리 스트림이므로 항상 먹싱 경로를
     탄다고 가정한다).
2. **downloading**: 각 스트림을 앱 캐시 디렉토리(`path_provider`의
   `getTemporaryDirectory()`) 아래 임시 파일로 다운로드한다. mp4의 경우
   영상 스트림을 먼저 받고 이어서 오디오 스트림을 받는 순차 방식으로
   구현한다(항목당 동시 다운로드 로직을 단순하게 유지하기 위함이며, 이미
   항목 단위로 최대 3개 병렬 처리가 이루어지고 있음). 진행률은 두 스트림의
   바이트 합산 기준으로 계산한다.
3. **processing**: 상태를 `processing`으로 전환하고 ffmpeg를 실행한다.
   - mp3: `-i audio.tmp -vn -b:a {bitrate} out.mp3`
   - mp4: `-i video.tmp -i audio.tmp -c:v copy -c:a aac out.mp4`
     (영상은 재인코딩 없이 copy, 오디오만 aac로 트랜스코딩하여 컨테이너
     호환성을 맞춘다)
4. **저장**: ffmpeg 출력 파일을 `saf` 패키지로 사용자가 선택한 폴더에 쓴다.
   기록이 끝나면 임시 파일(다운로드 원본 + ffmpeg 입력)을 삭제한다.
5. 상태를 `done`으로 전환하고 `filePath`(또는 SAF URI)를 `DownloadItem`에
   기록한다. 실패 시 각 단계에서 기존과 동일하게 `error` 상태로 전환하고
   `errorMsg`를 채우며, 남은 임시 파일을 정리한다.

## 에러 처리

- ffmpeg 실행 실패(비정상 종료 코드), SAF 쓰기 실패(사용자가 권한을 취소한
  경우 등)는 모두 기존과 동일하게 `DownloadStatus.error` + `errorMsg`로
  노출한다.
- 요청 화질의 스트림이 없는 경우는 에러가 아니라 자동 대체 처리하고, 실제
  적용된 화질을 카드에 표시한다(위 데이터 모델 섹션 참고).

## Android 설정 변경

- `ffmpeg_kit_flutter_new`의 네이티브 라이브러리 포함으로 APK 용량이
  증가한다(대략 +20~40MB, ABI 필터링으로 축소 가능). 구현 단계에서
  `mobile/android/app/build.gradle.kts`의 `abiFilters` 설정을 검토한다.
- `saf` 패키지가 요구하는 매니페스트 항목(있는 경우)을 추가한다.

## 테스트 방침

- `download_service.dart`의 스트림 선택 로직(화질별 매칭 및 자동 대체)은
  순수 함수로 분리 가능한 부분은 유닛 테스트로 검증한다.
- ffmpeg 실행 및 SAF 쓰기는 실기기(또는 에뮬레이터)에서 수동으로 mp3/mp4 각
  화질 옵션을 다운로드해 재생 가능 여부를 확인한다(자동화된 통합 테스트
  대상 아님 — 네이티브 바이너리와 실제 스토리지 권한이 필요).
