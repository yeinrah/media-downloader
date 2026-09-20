"""
YouTube / Vimeo Downloader - 병렬 다운로드 지원
사용법:
  pip install yt-dlp
  python youtube_downloader.py
"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import threading
import os, sys, shutil, re
from concurrent.futures import ThreadPoolExecutor

# ── 패키지 자동 설치 ──────────────────────────────────
def _ensure(pkg, import_as=None):
    import importlib, subprocess
    try:
        importlib.import_module(import_as or pkg)
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", pkg, "--quiet"])

_ensure("yt_dlp",     "yt_dlp")
_ensure("curl_cffi",  "curl_cffi")  # Vimeo TLS 차단 우회용
import yt_dlp
try:
    from yt_dlp.networking.impersonate import ImpersonateTarget
    IMPERSONATE = ImpersonateTarget("chrome")
except Exception:
    IMPERSONATE = None

# ── FFmpeg ────────────────────────────────────────────
def get_ffmpeg_path():
    if getattr(sys, "frozen", False):
        p = os.path.join(sys._MEIPASS, "ffmpeg.exe")
        if os.path.exists(p): return p
    return shutil.which("ffmpeg")

def ffmpeg_available():
    return get_ffmpeg_path() is not None

# ── 상수 ──────────────────────────────────────────────
STATUS_WAITING  = "대기 중"
STATUS_FETCHING = "정보 수집 중"
STATUS_LOADING  = "다운로드 중"
STATUS_DONE     = "완료"
STATUS_ERROR    = "오류"

FORMAT_MAP = {
    "MP4 720p  (빠른 다운로드)": {"format": "best[height<=720][ext=mp4]/best[height<=720]/best"},
    "MP4 480p  (빠른 다운로드)": {"format": "best[height<=480][ext=mp4]/best[height<=480]/best"},
    "MP4 최고화질":              {"format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio"},
    "MP4 1080p":                 {"format": "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080]"},
    "MP3 음원만":                {
        "format": "bestaudio/best",
        "postprocessors": [{"key": "FFmpegExtractAudio",
                            "preferredcodec": "mp3", "preferredquality": "192"}],
    },
}
MAX_PARALLEL = 3
RE_M3U8  = re.compile(r"\.m3u8", re.IGNORECASE)


# ── 데이터 모델 ───────────────────────────────────────
class DownloadItem:
    def __init__(self, item_id, url, fmt, save_dir, referer=None):
        self.id       = item_id
        self.url      = url
        self.fmt      = fmt
        self.save_dir = save_dir
        self.referer  = referer
        self.status   = STATUS_WAITING
        self.progress = 0.0
        self.title    = (url[:52] + "...") if len(url) > 52 else url
        self.speed    = ""
        self.error    = ""


# ── 메인 앱 ───────────────────────────────────────────
class YouTubeDownloader:
    def __init__(self, root):
        self.root = root
        self.root.title("YouTube / Vimeo Downloader")
        self.root.resizable(False, False)
        self.root.configure(bg="#0f0f0f")

        self.save_path    = tk.StringVar(value=os.path.expanduser("~/Downloads"))
        self.format_var   = tk.StringVar(value="MP4 1080p")
        self.url_var      = tk.StringVar()
        self.parallel_var = tk.IntVar(value=3)
        self.naver_var    = tk.BooleanVar(value=False)

        self.items: list[DownloadItem] = []
        self.item_id = 0
        self.lock    = threading.Lock()
        self.executor = ThreadPoolExecutor(max_workers=MAX_PARALLEL)

        self._build_ui()
        self.root.update_idletasks()
        self.root.minsize(720, self.root.winfo_reqheight())
        self._refresh_loop()
        self.url_var.trace_add("write", self._on_url_change)

    # ── UI ────────────────────────────────────────────
    def _build_ui(self):
        CARD  = "#1a1a1a"
        RED   = "#ff0000"
        WHITE = "#ffffff"
        GRAY  = "#888888"
        LIGHT = "#cccccc"

        # 헤더
        hdr = tk.Frame(self.root, bg=RED, height=52)
        hdr.pack(fill="x", side="top")
        hdr.pack_propagate(False)
        tk.Label(hdr, text="▶  YouTube / Vimeo Downloader",
                 font=("Arial Black", 13, "bold"), bg=RED, fg=WHITE
                 ).pack(side="left", padx=18, pady=12)
        bbg = "#007700" if ffmpeg_available() else "#994400"
        tk.Label(hdr, text="FFmpeg ✔" if ffmpeg_available() else "FFmpeg ✘",
                 font=("Arial", 9), bg=bbg, fg=WHITE, padx=8, pady=4
                 ).pack(side="right", padx=14)

        # 입력 패널
        inp = tk.Frame(self.root, bg=CARD, padx=20, pady=14)
        inp.pack(fill="x", padx=20, pady=(10, 0))
        inp.columnconfigure(1, weight=1)

        # URL 행
        tk.Label(inp, text="영상 URL", font=("Arial", 9, "bold"),
                 bg=CARD, fg=GRAY, width=8, anchor="w"
                 ).grid(row=0, column=0, sticky="w", pady=(0, 4))

        uf = tk.Frame(inp, bg=CARD)
        uf.grid(row=0, column=1, columnspan=3, sticky="ew", pady=(0, 4))
        self.url_entry = tk.Entry(
            uf, textvariable=self.url_var,
            font=("Consolas", 11), bg="#2a2a2a", fg=WHITE,
            insertbackground=WHITE, relief="flat",
            bd=0, highlightthickness=1,
            highlightbackground="#333333", highlightcolor=RED)
        self.url_entry.pack(side="left", fill="x", expand=True, ipady=8, ipadx=8)
        self.add_btn = tk.Button(
            uf, text="＋  큐에 추가",
            font=("Arial", 9, "bold"), bg=RED, fg=WHITE,
            relief="flat", cursor="hand2",
            command=self._add_to_queue, padx=10)
        self.add_btn.pack(side="left", padx=(6, 0))

        # 네이버 카페 체크박스
        nf = tk.Frame(inp, bg=CARD)
        nf.grid(row=1, column=1, columnspan=3, sticky="w", pady=(0, 4))
        tk.Checkbutton(
            nf,
            text="네이버 카페에 있는 Vimeo 영상이에요",
            variable=self.naver_var,
            font=("Arial", 9), bg=CARD, fg="#88ccff",
            selectcolor="#1a1a1a", activebackground=CARD,
            activeforeground="#aaddff", cursor="hand2"
        ).pack(side="left")
        tk.Label(nf, text="(체크하면 자동으로 카페 연결 처리)", font=("Arial", 8),
                 bg=CARD, fg="#555555").pack(side="left", padx=(6, 0))

        # URL 힌트
        self.url_hint = tk.Label(inp, text="", font=("Arial", 8),
                                 bg=CARD, fg="#888888", anchor="w")
        self.url_hint.grid(row=2, column=1, columnspan=3, sticky="w", pady=(0, 4))

        # 형식 / 동시 다운로드
        tk.Label(inp, text="형식", font=("Arial", 9, "bold"),
                 bg=CARD, fg=GRAY, width=8, anchor="w"
                 ).grid(row=3, column=0, sticky="w", pady=(0, 8))
        ttk.Combobox(inp, textvariable=self.format_var,
                     values=list(FORMAT_MAP.keys()),
                     state="readonly", font=("Arial", 10), width=28
                     ).grid(row=3, column=1, sticky="w", pady=(0, 8))
        tk.Label(inp, text="동시 다운로드", font=("Arial", 9, "bold"),
                 bg=CARD, fg=GRAY, anchor="w"
                 ).grid(row=3, column=2, sticky="e", padx=(20, 6), pady=(0, 8))
        sf = tk.Frame(inp, bg=CARD)
        sf.grid(row=3, column=3, sticky="w", pady=(0, 8))
        tk.Spinbox(sf, from_=1, to=MAX_PARALLEL, textvariable=self.parallel_var,
                   width=3, font=("Arial", 11), bg="#2a2a2a", fg=WHITE,
                   buttonbackground="#333333", relief="flat",
                   insertbackground=WHITE).pack(side="left")
        tk.Label(sf, text="개", font=("Arial", 9),
                 bg=CARD, fg=GRAY).pack(side="left", padx=(4, 0))

        # 저장 위치
        tk.Label(inp, text="저장 위치", font=("Arial", 9, "bold"),
                 bg=CARD, fg=GRAY, width=8, anchor="w"
                 ).grid(row=4, column=0, sticky="w")
        pf = tk.Frame(inp, bg=CARD)
        pf.grid(row=4, column=1, columnspan=3, sticky="ew")
        tk.Entry(pf, textvariable=self.save_path,
                 font=("Consolas", 10), bg="#2a2a2a", fg=LIGHT,
                 insertbackground=WHITE, relief="flat",
                 bd=0, highlightthickness=1,
                 highlightbackground="#333333", highlightcolor=RED
                 ).pack(side="left", fill="x", expand=True, ipady=7, ipadx=8)
        tk.Button(pf, text="폴더 선택", font=("Arial", 9),
                  bg="#333333", fg=LIGHT, relief="flat", cursor="hand2",
                  command=self._browse_folder, padx=8
                  ).pack(side="left", padx=(6, 0))

        # 큐 컨트롤
        cf = tk.Frame(self.root, bg="#0f0f0f")
        cf.pack(fill="x", padx=20, pady=6)
        tk.Button(cf, text="✕  완료 항목 지우기", font=("Arial", 9),
                  bg="#2a2a2a", fg=GRAY, relief="flat", cursor="hand2",
                  command=self._clear_done, padx=10, pady=6
                  ).pack(side="left")
        self.queue_label = tk.Label(cf, text="큐: 0개",
                                    font=("Arial", 9), bg="#0f0f0f", fg=GRAY)
        self.queue_label.pack(side="right")

        # 다운로드 버튼 (하단 고정)
        bf = tk.Frame(self.root, bg="#0f0f0f")
        bf.pack(fill="x", side="bottom", padx=20, pady=12)
        self.dl_btn = tk.Button(
            bf, text="⬇  전체 다운로드 시작",
            font=("Arial Black", 12, "bold"),
            bg=RED, fg=WHITE, relief="flat", cursor="hand2",
            height=2, command=self._start_all,
            activebackground="#cc0000", activeforeground=WHITE)
        self.dl_btn.pack(fill="x")

        # 큐 목록
        qo = tk.Frame(self.root, bg="#0f0f0f")
        qo.pack(fill="both", expand=True, padx=20, pady=(0, 6))
        tk.Label(qo, text="다운로드 큐", font=("Arial", 9, "bold"),
                 bg="#0f0f0f", fg=GRAY).pack(anchor="w", pady=(0, 4))
        cf2 = tk.Frame(qo, bg="#1a1a1a",
                       highlightthickness=1, highlightbackground="#333333")
        cf2.pack(fill="both", expand=True)
        self.canvas = tk.Canvas(cf2, bg="#1a1a1a",
                                highlightthickness=0, height=200)
        sb = ttk.Scrollbar(cf2, orient="vertical", command=self.canvas.yview)
        self.canvas.configure(yscrollcommand=sb.set)
        sb.pack(side="right", fill="y")
        self.canvas.pack(side="left", fill="both", expand=True)
        self.queue_frame = tk.Frame(self.canvas, bg="#1a1a1a")
        self.canvas_window = self.canvas.create_window(
            (0, 0), window=self.queue_frame, anchor="nw")
        self.queue_frame.bind("<Configure>", self._on_frame_configure)
        self.canvas.bind("<Configure>", self._on_canvas_configure)
        self.empty_label = tk.Label(
            self.queue_frame,
            text="URL을 입력하고 '큐에 추가'를 눌러보세요.",
            font=("Arial", 10), bg="#1a1a1a", fg="#555555")
        self.empty_label.pack(pady=30)
        self.row_widgets: dict[int, dict] = {}

    # ── URL 변경 감지 ─────────────────────────────────
    def _on_url_change(self, *_):
        url = self.url_var.get().strip()
        if RE_M3U8.search(url):
            self.url_hint.config(
                text="🎬 스트림 링크(m3u8) 감지 — referrer가 필요한 경우 자동으로 설정돼요.",
                fg="#88ccff")
        elif "vimeo.com" in url:
            self.url_hint.config(
                text="🎬 Vimeo 링크 감지 — 네이버 카페 영상이면 아래 체크박스를 켜주세요.",
                fg="#88ccff")
            self.naver_var.set(True)   # vimeo 링크 입력 시 자동 체크
        else:
            self.naver_var.set(False)
            self.url_hint.config(text="", fg="#888888")

    # ── 이벤트 ────────────────────────────────────────
    def _browse_folder(self):
        folder = filedialog.askdirectory(initialdir=self.save_path.get())
        if folder:
            self.save_path.set(folder)

    def _add_to_queue(self):
        url = self.url_var.get().strip()
        if not url:
            messagebox.showwarning("입력 오류", "URL을 입력해 주세요.")
            return
        if not url.startswith("http"):
            messagebox.showwarning("입력 오류", "올바른 URL을 입력해 주세요.")
            return

        fmt = self.format_var.get()
        if "빠른 다운로드" not in fmt and not ffmpeg_available():
            if not messagebox.askyesno(
                "FFmpeg 없음",
                "선택한 형식은 FFmpeg가 필요합니다.\n"
                "'MP4 720p (빠른 다운로드)'로 변경하고 추가할까요?"
            ):
                return
            fmt = "MP4 720p  (빠른 다운로드)"
            self.format_var.set(fmt)

        # 네이버 카페 체크 시 referer 자동 설정
        referer = "https://cafe.naver.com" if self.naver_var.get() else None
        self.item_id += 1
        item = DownloadItem(self.item_id, url, fmt, self.save_path.get(),
                            referer=referer)
        with self.lock:
            self.items.append(item)
        self._add_row(item)
        self.url_var.set("")
        self.url_entry.focus()
        self.root.after(50, self._on_frame_configure)

    # ── 큐 행 렌더링 ──────────────────────────────────
    def _add_row(self, item: DownloadItem):
        if self.empty_label.winfo_ismapped():
            self.empty_label.pack_forget()

        GRAY  = "#888888"
        LIGHT = "#cccccc"

        row = tk.Frame(self.queue_frame, bg="#222222",
                       highlightthickness=1, highlightbackground="#333333")
        row.pack(fill="x", padx=6, pady=3)
        row.columnconfigure(1, weight=1)

        # 번호
        tk.Label(row, text=f"#{item.id}", font=("Arial", 8),
                 bg="#222222", fg=GRAY, width=4
                 ).grid(row=0, column=0, rowspan=2, padx=(8, 6), pady=8, sticky="n")

        # 제목
        title_lbl = tk.Label(row, text=item.title, font=("Consolas", 9),
                             bg="#222222", fg=LIGHT, anchor="w")
        title_lbl.grid(row=0, column=1, sticky="ew", padx=(0, 8), pady=(8, 2))

        # 상태
        info_f = tk.Frame(row, bg="#222222")
        info_f.grid(row=1, column=1, sticky="ew", padx=(0, 8), pady=(0, 6))
        status_lbl = tk.Label(info_f, text=item.status, font=("Arial", 8),
                              bg="#222222", fg=GRAY, anchor="w")
        status_lbl.pack(side="left")
        speed_lbl = tk.Label(info_f, text="", font=("Arial", 8),
                             bg="#222222", fg=GRAY)
        speed_lbl.pack(side="left", padx=(10, 0))

        # 프로그레스 바
        style = ttk.Style()
        style.configure("Q.Horizontal.TProgressbar",
                        troughcolor="#333333", background="#ff0000", thickness=4)
        pb = ttk.Progressbar(row, maximum=100, value=0,
                             style="Q.Horizontal.TProgressbar", length=180)
        pb.grid(row=0, column=2, rowspan=2, padx=(0, 8), pady=8)

        del_btn = tk.Button(row, text="✕", font=("Arial", 9),
                            bg="#333333", fg=GRAY, relief="flat", cursor="hand2",
                            command=lambda i=item.id: self._remove_item(i),
                            padx=6, pady=2)
        del_btn.grid(row=0, column=3, rowspan=2, padx=(0, 8))

        self.row_widgets[item.id] = {
            "row": row, "title": title_lbl,
            "status": status_lbl, "speed": speed_lbl,
            "pb": pb, "del": del_btn,
        }

    # ── 새로고침 ──────────────────────────────────────
    def _refresh_loop(self):
        self._update_rows()
        self.root.after(100, self._refresh_loop)

    def _update_rows(self):
        with self.lock:
            items = list(self.items)

        waiting = sum(1 for i in items if i.status == STATUS_WAITING)
        active  = sum(1 for i in items if i.status in (STATUS_LOADING, STATUS_FETCHING))
        self.queue_label.config(
            text=f"큐: {len(items)}개  |  대기: {waiting}  |  진행: {active}")

        COLOR = {
            STATUS_WAITING:  "#888888",
            STATUS_FETCHING: "#ffcc00",
            STATUS_LOADING:  "#44aaff",
            STATUS_DONE:     "#44cc44",
            STATUS_ERROR:    "#ff4444",
        }
        for item in items:
            w = self.row_widgets.get(item.id)
            if not w: continue

            if item.status == STATUS_ERROR and item.error:
                short = item.error[:70] + ("..." if len(item.error) > 70 else "")
                w["status"].config(
                    text=f"오류: {short}",
                    fg=COLOR[STATUS_ERROR],
                    cursor="hand2")
                w["status"].bind(
                    "<Button-1>",
                    lambda e, err=item.error: (
                        self.root.clipboard_clear(),
                        self.root.clipboard_append(err),
                        messagebox.showinfo("오류 상세 (클립보드에 복사됨)", err)
                    ))
            else:
                w["status"].config(
                    text=item.status,
                    fg=COLOR.get(item.status, "#888888"),
                    cursor="")

            w["speed"].config(text=item.speed)
            w["pb"]["value"] = item.progress
            disp = (item.title[:65] + "...") if len(item.title) > 65 else item.title
            w["title"].config(text=disp)

        is_running = any(i.status in (STATUS_LOADING, STATUS_FETCHING)
                         for i in items)
        if is_running:
            self.dl_btn.config(text="⏳  다운로드 중...", bg="#444444", state="disabled")
        else:
            self.dl_btn.config(text="⬇  전체 다운로드 시작", bg="#ff0000", state="normal")

    # ── 큐 관리 ───────────────────────────────────────
    def _on_frame_configure(self, event=None):
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))

    def _on_canvas_configure(self, event):
        self.canvas.itemconfig(self.canvas_window, width=event.width)

    def _remove_item(self, item_id):
        with self.lock:
            self.items = [i for i in self.items if i.id != item_id]
        w = self.row_widgets.pop(item_id, None)
        if w: w["row"].destroy()
        if not self.items:
            self.empty_label.pack(pady=30)

    def _clear_done(self):
        with self.lock:
            done_ids = [i.id for i in self.items
                        if i.status in (STATUS_DONE, STATUS_ERROR)]
        for iid in done_ids:
            self._remove_item(iid)

    # ── 다운로드 ──────────────────────────────────────
    def _start_all(self):
        with self.lock:
            waiting = [i for i in self.items if i.status == STATUS_WAITING]
        if not waiting:
            messagebox.showinfo("알림", "대기 중인 항목이 없습니다.")
            return
        n = self.parallel_var.get()
        self.executor = ThreadPoolExecutor(max_workers=n)
        sem = threading.Semaphore(n)

        def run(item):
            sem.acquire()
            try: self._download_item(item)
            finally: sem.release()

        for item in waiting:
            self.executor.submit(run, item)

    def _download_item(self, item: DownloadItem):
        item.status   = STATUS_FETCHING
        item.progress = 0

        def progress_hook(d):
            if d["status"] == "downloading":
                total = d.get("total_bytes") or d.get("total_bytes_estimate", 0)
                dl    = d.get("downloaded_bytes", 0)
                speed = d.get("speed") or 0
                if total > 0:
                    item.progress = dl / total * 100
                item.speed  = f"{speed/1024/1024:.1f} MB/s" if speed else ""
                item.status = STATUS_LOADING
                fname = os.path.splitext(
                    os.path.basename(d.get("filename", "")))[0]
                if fname: item.title = fname
            elif d["status"] == "finished":
                item.progress = 100
                item.speed    = ""
                item.status   = STATUS_LOADING

        fp = get_ffmpeg_path()

        # m3u8 스트림 여부 감지
        is_m3u8  = bool(RE_M3U8.search(item.url))
        is_vimeo = "vimeo" in item.url

        extra_headers = {}
        if is_vimeo or is_m3u8:
            # 사용자가 카페 URL 입력한 경우 그걸 referer로, 아니면 vimeo player로
            referer_url = item.referer or "https://player.vimeo.com/"
            extra_headers = {
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/124.0.0.0 Safari/537.36"
                ),
                "Referer": referer_url,
                "Origin":  referer_url.rstrip("/"),
            }

        # m3u8 직접 링크 또는 Vimeo 직접 링크는 포맷 지정 없이 best로 고정
        # (포맷 지정 시 "Requested format is not available" 오류 발생)
        if is_m3u8 or is_vimeo:
            fmt_opts = {"format": "best"}
        else:
            fmt_opts = FORMAT_MAP.get(item.fmt, FORMAT_MAP["MP4 1080p"])

        ydl_opts = {
            "outtmpl":               os.path.join(item.save_dir, "%(title)s.%(ext)s"),
            "progress_hooks":        [progress_hook],
            "quiet":                 True,
            "no_warnings":           True,
            "no_check_certificates": True,
            **({"ffmpeg_location": os.path.dirname(fp)} if fp else {}),
            **({"http_headers": extra_headers} if extra_headers else {}),
            # Vimeo TLS 핑거프린트 차단 우회
            **({"impersonate": IMPERSONATE} if (is_vimeo or is_m3u8) and IMPERSONATE else {}),
            **fmt_opts,
        }

        try:
            # 제목만 가져올 때는 포맷 없이 (포맷 검증 오류 방지)
            info_opts = {k: v for k, v in ydl_opts.items()
                         if k not in ("format", "postprocessors")}
            with yt_dlp.YoutubeDL(info_opts) as ydl:
                try:
                    info = ydl.extract_info(item.url, download=False)
                    if info:
                        item.title = info.get("title", item.title)
                except Exception:
                    pass  # 제목 못 가져와도 다운로드는 시도

            item.status = STATUS_LOADING

            # 실제 다운로드는 포맷 포함된 옵션으로
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([item.url])

            item.status   = STATUS_DONE
            item.progress = 100
            item.speed    = ""
        except Exception as e:
            item.status = STATUS_ERROR
            item.error  = str(e)
            item.speed  = ""


# ── 진입점 ────────────────────────────────────────────
if __name__ == "__main__":
    root = tk.Tk()
    app  = YouTubeDownloader(root)
    root.bind("<Return>", lambda e: app._add_to_queue())
    root.mainloop()
