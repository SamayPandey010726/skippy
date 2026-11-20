"""Prepare individually playable native recordings and verify the requested format."""
import html
import json
from pathlib import Path
import subprocess
import sys

TITLES = [
    "Floating wheel", "Keyboard and themes", "Settings", "File Shelf", "Clipboard",
    "Extract text", "Pick colour", "Timer", "Notes", "QR generator", "QR scanner",
    "Search", "Apps", "Music", "Downloads", "Stay awake", "Recent actions", "Mac",
    "Calendar", "Calculator", "Screenshots", "Draw on screen",
]


def inspect(path):
    output = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
        "format=duration:stream=width,height", "-of", "json", str(path),
    ])
    info = json.loads(output)
    video = info["streams"][0]
    return float(info["format"]["duration"]), (video["width"], video["height"])


ATTACHMENTS = ["Left edge", "Right edge", "Top edge", "Bottom edge", "Notch", "Menu bar", "Dock"]


def timestamp(marker):
    return float(marker.read_text().strip() or marker.stat().st_mtime)


def package(source, destination, titles=TITLES):
    destination.mkdir(parents=True, exist_ok=True)
    cards = []
    for index, title in enumerate(titles, 1):
        path = source / title / "WindowServer.mp4"
        duration, size = inspect(path)
        start, stop = (path.parent / f"capture.{event}" for event in ("ready", "finished"))
        elapsed = timestamp(stop) - timestamp(start)
        timeline = max(duration, elapsed)
        if duration <= 0 or timeline < 15 or size != (1920, 1080):
            raise ValueError(f"{title} captured at {size} for {timeline:.2f} seconds")
        name = f"{index:02}-{title.lower().replace(' ', '-')}.mp4"
        movie = destination / name
        # ScreenCaptureKit stops emitting frames when the desktop is stationary.
        # Restore that observed idle time from the recorder's start and finish callbacks.
        timing = min(1, 18 / timeline)
        filters = f"fps=30,tpad=stop_mode=clone:stop_duration={max(0, elapsed-duration):.4f},setpts={timing}*PTS,fps=30"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-an",
                        "-vf", filters, "-c:v", "libx264", "-threads", "3",
                        "-crf", "17", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(movie)], check=True)
        length, shape = inspect(movie)
        if not 15 <= length <= 20 or shape != (1920, 1080):
            raise ValueError(f"Invalid export {movie.name}: {shape}, {length:.2f} seconds")
        cover = movie.with_suffix(".jpg")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "8", "-i", str(movie), "-frames:v", "1",
                        "-vf", "scale=640:360", str(cover)], check=True)
        cards.append(f'<article><h2>{html.escape(title)}</h2><video controls preload="none" poster="{cover.name}" src="{name}"></video>'
                     f'<p>{length:.1f} seconds · <a href="{name}" download>Download MP4</a></p></article>')
    (destination / "index.html").write_text(
        '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>Skippy · Mac review</title><style>:root{color-scheme:light dark}body{font:16px system-ui;max-width:1200px;'
        'margin:3rem auto;padding:0 1.5rem}main{display:grid;gap:2rem;grid-template-columns:repeat(auto-fit,minmax(min(100%,320px),1fr))}'
        'h2{font-size:1.1rem}video{display:block;width:100%;aspect-ratio:16/9;border-radius:12px}p{font-size:.88rem}'
        '</style><h1>Skippy for Mac</h1><p>Recorded on the macOS desktop. Each film shows the live controls in a 1080p frame.</p><main>'
        + ''.join(cards) + '</main></html>', encoding='utf-8')
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(destination / "01-floating-wheel.mp4"),
                    "-filter_complex", "fps=15,scale=600:-1,split[a][b];[a]palettegen[p];[b][p]paletteuse",
                    str(destination / "Floating-wheel.gif")], check=True)


if __name__ == "__main__":
    titles = TITLES + ATTACHMENTS if "--with-attachments" in sys.argv[3:] else TITLES
    package(Path(sys.argv[1]), Path(sys.argv[2]), titles)
