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


def package(source, destination):
    destination.mkdir(parents=True, exist_ok=True)
    cards = []
    for index, title in enumerate(TITLES, 1):
        path = source / title / "WindowServer.mp4"
        duration, size = inspect(path)
        if duration < 15 or size != (1920, 1080):
            raise ValueError(f"{title} captured at {size} for {duration:.2f} seconds")
        name = f"{index:02}-{title.lower().replace(' ', '-')}.mp4"
        movie = destination / name
        # Preserve the full interaction if a system panel takes longer to respond.
        timing = min(1, 18 / duration)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-an",
                        "-vf", f"setpts={timing}*PTS,fps=30", "-c:v", "libx264",
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
    package(Path(sys.argv[1]), Path(sys.argv[2]))
