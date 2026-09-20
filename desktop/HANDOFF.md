# YouTube / Vimeo Downloader — Claude Code 인수인계 문서

## 프로젝트 개요
YouTube와 네이버 카페 임베드 Vimeo 영상을 다운받는 Python GUI 데스크탑 앱.
tkinter 기반 UI, yt-dlp로 다운로드, FFmpeg로 영상/음성 합치기.

---

## 파일 구성

| 파일 | 역할 |
|---|---|
| `youtube_downloader.py` | 메인 프로그램 |
| `run.bat` | Python 환경에서 바로 실행하는 런처 |
| `build_exe.bat` | PyInstaller로 단독 실행 EXE 빌드 |

---

## 현재 기능

- YouTube / Vimeo / m3u8 URL 다운로드
- 병렬 다운로드 (최대 3개 동시)
- 다운로드 큐 UI (진행률, 속도, 상태 표시)
- 포맷 선택 (MP4 720p/480p/1080p/최고화질, MP3)
- FFmpeg 자동 감지 및 EXE 번들
- 오류 시 클릭으로 상세 메시지 확인
- "네이버 카페 Vimeo 영상" 체크박스 → Referer 자동 설정
- curl_cffi로 Vimeo TLS 핑거프린트 우회 시도

---

## 현재 미해결 문제 (최우선 과제)

### 네이버 카페 임베드 Vimeo 영상 다운로드 실패

**증상:**
```
ERROR: [generic] playlist: Requested format is not available.
Use --list-formats for a list of available formats
```

**재현 방법:**
1. `https://player.vimeo.com/video/1222153458?h=427c680fed&app_id=122963` 입력
2. "네이버 카페에 있는 Vimeo 영상이에요" 체크박스 체크
3. 큐에 추가 → 전체 다운로드 시작

**시도한 것들:**
- `format: "best"` 고정 → 코드상 적용돼 있으나 오류 지속
- `extract_info`와 `download` 분리 (포맷 검증 오류 방지 목적)
- `curl_cffi` + `ImpersonateTarget("chrome")` 추가
- `no_check_certificates: True`
- Referer를 `https://cafe.naver.com`으로 설정
- http_headers에 User-Agent, Origin 추가

**의심 원인:**
- Vimeo embed-only 영상은 player URL(`player.vimeo.com/video/...`)로 접근 시
  yt-dlp가 내부적으로 Vimeo API를 호출하는데, 이때 m3u8 playlist를 받아오고
  해당 playlist에서 포맷을 선택하는 과정에서 실패하는 것으로 추정
- `format: "best"`가 실제로 ydl_opts에 반영되고 있는지 확인 필요
- 또는 Vimeo가 IP/TLS 레벨에서 차단해서 playlist 자체를 못 받아오는 것일 수도 있음

**다음 시도 방향:**
1. `yt-dlp --list-formats "player.vimeo.com/..."` 로 실제 로컬에서 사용 가능한 포맷 목록 확인
2. 포맷을 `"bestvideo+bestaudio/best"` 또는 아예 format 키 자체를 제거하고 테스트
3. m3u8 URL을 직접 따서 (F12 → Network → .m3u8 필터) 프로그램에 입력하는 방식도 지원 중 — 이 경우는 작동 가능성 있음
4. `yt-dlp`에 `--referer` 옵션과 함께 로컬 CLI에서 직접 테스트해서 성공하는 옵션 조합을 먼저 찾은 뒤 코드에 반영할 것

---

## 핵심 다운로드 로직 (youtube_downloader.py)

```python
# _download_item 메서드 핵심 부분

is_m3u8  = bool(RE_M3U8.search(item.url))   # .m3u8 포함 여부
is_vimeo = "vimeo" in item.url

# Vimeo / m3u8은 best로 고정 (포맷 지정 시 오류)
if is_m3u8 or is_vimeo:
    fmt_opts = {"format": "best"}
else:
    fmt_opts = FORMAT_MAP.get(item.fmt, FORMAT_MAP["MP4 1080p"])

# Referer: 체크박스 켜면 cafe.naver.com, 아니면 player.vimeo.com
referer_url = item.referer or "https://player.vimeo.com/"

ydl_opts = {
    "format": "best",                        # ← 이게 실제로 적용되는지 의심
    "http_headers": { "Referer": referer_url, ... },
    "impersonate": ImpersonateTarget("chrome"),
    "no_check_certificates": True,
    ...
}

# extract_info(포맷 없이) → 제목만 수집
# download(포맷 포함) → 실제 다운로드
```

---

## 의존성

```
pip install yt-dlp curl_cffi
```

EXE 빌드 시 추가:
```
pip install pyinstaller
```

FFmpeg: `build_exe.bat` 실행 시 자동 다운로드 및 번들

---

## UI 구조

```
[헤더: YouTube/Vimeo Downloader]           [FFmpeg ✔/✘]
┌─────────────────────────────────────────────────────┐
│ 영상 URL  [입력창____________________________] [＋큐에추가]│
│           ☐ 네이버 카페에 있는 Vimeo 영상이에요        │
│           (체크하면 자동으로 카페 연결 처리)            │
│ 형식      [MP4 1080p ▼]    동시 다운로드 [3] 개        │
│ 저장 위치 [C:\Users\...\Downloads___] [폴더 선택]      │
└─────────────────────────────────────────────────────┘
[✕ 완료 항목 지우기]                        큐: 0개
┌─────────────────────────────────────────────────────┐
│ 다운로드 큐 (스크롤 가능)                              │
│ #1  영상제목...          [======    ] 60%  ✕         │
│ #2  대기 중                                  ✕       │
└─────────────────────────────────────────────────────┘
[         ⬇  전체 다운로드 시작          ]  ← 하단 고정
```

---

## 참고: 로컬 CLI 테스트 명령어

Vimeo embed-only 영상 테스트용:
```bash
# 기본 시도
yt-dlp --referer "https://cafe.naver.com" \
       --add-header "Origin:https://cafe.naver.com" \
       --no-check-certificates \
       "https://player.vimeo.com/video/1222153458?h=427c680fed&app_id=122963"

# 포맷 목록 확인
yt-dlp --list-formats \
       --referer "https://cafe.naver.com" \
       "https://player.vimeo.com/video/1222153458?h=427c680fed&app_id=122963"

# curl_cffi impersonation 사용
yt-dlp --impersonate chrome \
       --referer "https://cafe.naver.com" \
       "https://player.vimeo.com/video/1222153458?h=427c680fed&app_id=122963"
```

m3u8 직접 URL (F12에서 따온 경우):
```bash
yt-dlp --referer "https://player.vimeo.com/" \
       "https://vod-adaptive-ak.vimeocdn.com/.../playlist.m3u8?..."
```
> ⚠️ m3u8 URL은 만료 시간(exp=...)이 있어서 복사 후 즉시 실행해야 함
