@echo off
chcp 65001 > nul
title YouTube Downloader

echo.
echo  ▶ YouTube Downloader 시작 중...
echo.

:: Python 설치 확인
python --version > nul 2>&1
if errorlevel 1 (
    echo  [오류] Python이 설치되어 있지 않습니다.
    echo.
    echo  아래 주소에서 Python을 설치해 주세요:
    echo  https://www.python.org/downloads/
    echo.
    echo  설치 시 "Add Python to PATH" 반드시 체크!
    echo.
    pause
    exit /b 1
)

:: yt-dlp 설치 또는 업데이트
echo  [1/2] 필요한 패키지 확인 중...
python -c "import yt_dlp" > nul 2>&1
if errorlevel 1 (
    echo  yt-dlp 설치 중...
    python -m pip install yt-dlp --quiet
    if errorlevel 1 (
        echo  [오류] yt-dlp 설치 실패. 인터넷 연결을 확인해 주세요.
        pause
        exit /b 1
    )
    echo  yt-dlp 설치 완료!
) else (
    echo  yt-dlp 이미 설치됨 - 최신 버전 확인 중...
    python -m pip install yt-dlp --upgrade --quiet
)

:: 프로그램 실행
echo  [2/2] 프로그램 실행 중...
echo.
python youtube_downloader.py

if errorlevel 1 (
    echo.
    echo  [오류] 프로그램 실행 중 문제가 발생했습니다.
    pause
)
