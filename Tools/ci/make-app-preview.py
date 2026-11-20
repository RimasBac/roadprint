"""Cut the simulator recording into an App Store app preview.

Usage: python3 make-app-preview.py RAW.mov RECORD_STOP.txt XCODEBUILD.log OUT.mp4

AppPreviewTests prints `RP_PREVIEW_KEEP_BEGIN t` and `RP_PREVIEW_KEEP_END t` (Unix seconds) around
each block worth showing. RECORD_STOP holds the Unix time at which the recording was stopped,
which is the end of RAW.mov (the recorder's own start message comes too early to sync on). The
blocks are joined in order and encoded for the 6.9-inch iPhone slot: 886 x 1920 portrait, 30 fps,
H.264 High, a silent stereo AAC track, 15 to 30 seconds long.
"""
import json
import re
import subprocess
import sys

WIDTH, HEIGHT, FPS = 886, 1920, 30
MIN_SECONDS, MAX_SECONDS = 15.0, 29.5
# Small margins so a cut never lands on half a transition.
LEAD, TAIL = 0.15, 0.1


def blocks(log, start):
    begins = [float(t) for t in re.findall(r'RP_PREVIEW_KEEP_BEGIN ([0-9.]+)', log)]
    ends = [float(t) for t in re.findall(r'RP_PREVIEW_KEEP_END ([0-9.]+)', log)]
    if not begins or len(begins) != len(ends):
        raise SystemExit(f'unmatched preview markers: {len(begins)} begin, {len(ends)} end')
    result = []
    for b, e in zip(begins, ends):
        if e <= b:
            raise SystemExit(f'empty preview block {b}..{e}')
        result.append([max(0.0, b - start - LEAD), e - start + TAIL])
    return result


def fit(segments):
    """Shorten every block by the same share when the tour runs over Apple's 30-second limit."""
    total = sum(e - b for b, e in segments)
    if total < MIN_SECONDS:
        raise SystemExit(f'preview is {total:.1f} s; App Store previews need at least {MIN_SECONDS:.0f} s')
    if total > MAX_SECONDS:
        share = MAX_SECONDS / total
        segments = [[b, b + (e - b) * share] for b, e in segments]
    return segments


def duration(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', path],
                         check=True, capture_output=True, text=True).stdout
    return float(json.loads(out)['format']['duration'])


def main(raw, stop_file, log_file, out):
    start = float(open(stop_file).read()) - duration(raw)
    segments = fit(blocks(open(log_file, errors='replace').read(), start))
    # A 1320 x 2868 or 1178 x 2556 capture scales to 886 wide and a few rows over 1920; the crop
    # takes them off the top and bottom.
    parts = [f'[0:v]trim=start={b:.3f}:end={e:.3f},setpts=PTS-STARTPTS[v{i}]' for i, (b, e) in enumerate(segments)]
    joined = ''.join(f'[v{i}]' for i in range(len(segments)))
    graph = ';'.join(parts + [
        f'{joined}concat=n={len(segments)}:v=1:a=0,fps={FPS},scale={WIDTH}:-2,'
        f'crop={WIDTH}:{HEIGHT},setsar=1,format=yuv420p[v]'])
    total = sum(e - b for b, e in segments)
    subprocess.run([
        'ffmpeg', '-y', '-v', 'error', '-i', raw,
        '-f', 'lavfi', '-t', f'{total:.3f}', '-i', 'anullsrc=channel_layout=stereo:sample_rate=48000',
        '-filter_complex', graph, '-map', '[v]', '-map', '1:a',
        '-c:v', 'libx264', '-profile:v', 'high', '-level', '4.0', '-preset', 'slow', '-crf', '16',
        '-r', str(FPS), '-c:a', 'aac', '-b:a', '256k', '-shortest', '-movflags', '+faststart', out,
    ], check=True)
    seconds = duration(out)
    if not MIN_SECONDS <= seconds <= 30.0:
        raise SystemExit(f'{out}: {seconds:.2f} s is outside 15 to 30 s')
    print(f'{out}: {WIDTH}x{HEIGHT}, {FPS} fps, {seconds:.2f} s from {len(segments)} blocks')


if __name__ == '__main__':
    if len(sys.argv) != 5:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
