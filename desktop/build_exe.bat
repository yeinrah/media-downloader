@echo off
title YouTube Downloader - Build

echo.
echo  [START] Building YouTubeDownloader.exe ...
echo.

python --version > nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Python is not installed.
    echo  Please install Python from https://www.python.org/downloads/
    echo  Make sure to check "Add Python to PATH" during installation.
    pause
    exit /b 1
)

echo  [1/4] Installing required packages...
python -m pip install pyinstaller yt-dlp curl_cffi --quiet --upgrade
if errorlevel 1 (
    echo  [ERROR] Package installation failed.
    pause
    exit /b 1
)
echo  Done.

echo  [2/4] Downloading FFmpeg...
if exist "ffmpeg_tmp" rmdir /s /q ffmpeg_tmp
mkdir ffmpeg_tmp

echo  Downloading FFmpeg (~50MB, please wait...
curl -L "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip" -o ffmpeg_tmp\ffmpeg.zip
if errorlevel 1 (
    echo  [ERROR] FFmpeg download failed. Check your internet connection.
    pause
    exit /b 1
)

echo  Extracting...
powershell -Command "Expand-Archive -Path 'ffmpeg_tmp\ffmpeg.zip' -DestinationPath 'ffmpeg_tmp' -Force"
for /r "ffmpeg_tmp" %%f in (ffmpeg.exe)  do copy "%%f" "ffmpeg_tmp\ffmpeg.exe"  > nul 2>&1
for /r "ffmpeg_tmp" %%f in (ffprobe.exe) do copy "%%f" "ffmpeg_tmp\ffprobe.exe" > nul 2>&1
echo  FFmpeg ready.

echo  [3/4] Building EXE (this may take 2-4 minutes)...
echo.
pyinstaller ^
    --onefile ^
    --windowed ^
    --name "YouTubeDownloader" ^
    --add-binary "ffmpeg_tmp\ffmpeg.exe;." ^
    --add-binary "ffmpeg_tmp\ffprobe.exe;." ^
    --hidden-import yt_dlp ^
    --hidden-import yt_dlp.extractor ^
    --hidden-import yt_dlp.postprocessor ^
    --hidden-import curl_cffi ^
    --collect-all yt_dlp ^
    --collect-all curl_cffi ^
    youtube_downloader.py

if errorlevel 1 (
    echo.
    echo  [ERROR] Build failed.
    rmdir /s /q ffmpeg_tmp
    pause
    exit /b 1
)

echo  [4/4] Cleaning up...
rmdir /s /q ffmpeg_tmp
rmdir /s /q build
del /q YouTubeDownloader.spec > nul 2>&1

echo.
echo  ================================================
echo   Build complete!
echo   Output: dist\YouTubeDownloader.exe
echo   (FFmpeg included - no installation needed)
echo  ================================================
echo.
explorer dist
pause
