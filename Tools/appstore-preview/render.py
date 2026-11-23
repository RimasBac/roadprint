"""Cut the App Store preview video from a screen recording of the real app.

The only picture source is the simulator recording made by record.sh while
AppStorePreviewTests ran. Nothing is drawn, mocked up or imported: each scene is a
trim of that recording, scaled to the preview size, with a text caption on top.
An optional music file contributes audio only.

  render.py stills  ...   frames of every scene, from the recording, for review before rendering
  render.py render  ...   the preview .mp4, a poster PNG and provenance.json, then verify
  render.py verify  ...   re-check a rendered preview against the recording
  render.py all     ...   stills, render and verify

Common arguments: --raw raw.mov --clock record-start.txt --markers MARKERS --out DIR
MARKERS is the preview-markers JSON, or an xcresult attachment export that contains it.
Needs ffmpeg and ffprobe.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCENES = Path(__file__).with_name('scenes.json')
VIDEO_NAME = 'roadprint-app-preview-886x1920.mp4'
# App Store Connect: 15–30 s, under 500 MB. 886×1920 portrait is the 6.9-inch iPhone size.
MIN_SECONDS, MAX_SECONDS, MAX_BYTES = 15.0, 30.0, 500 * 1024 * 1024
ALLOWED_SIZES = {(886, 1920)}
MAX_CAPTION = 40
# Mean absolute grey-level difference allowed between an output frame and the same moment of
# the recording, outside the caption band. Compression noise is about 1–3.
MATCH_LIMIT = 12.0


class HarnessError(Exception):
    pass


# ---------- configuration and plan (pure, unit-tested) ----------

def load_config(path=SCENES):
    config = json.loads(Path(path).read_text())
    _keys(config, {'output', 'caption', 'scenes'}, 'scenes.json')
    out = config['output']
    _keys(out, {'width', 'height', 'fps'}, 'output')
    if (out['width'], out['height']) not in ALLOWED_SIZES:
        raise HarnessError(f"output {out['width']}x{out['height']} is not an App Store preview size")
    if out['fps'] != 30:
        raise HarnessError('output fps must be 30')
    caption = config['caption']
    _keys(caption, {'font', 'size', 'y'}, 'caption')
    font = (REPO / caption['font']).resolve()
    if REPO not in font.parents or font.suffix != '.ttf':
        raise HarnessError('caption font must be a .ttf inside the repository')
    scenes = config['scenes']
    if not scenes:
        raise HarnessError('no scenes')
    ids = set()
    for scene in scenes:
        _keys(scene, {'id', 'mark', 'offset', 'seconds', 'caption'}, f"scene {scene.get('id')}")
        if scene['id'] in ids:
            raise HarnessError(f"duplicate scene id {scene['id']}")
        ids.add(scene['id'])
        if scene['seconds'] < 1.0 or scene['offset'] < 0:
            raise HarnessError(f"scene {scene['id']}: seconds must be ≥ 1 and offset ≥ 0")
        if not isinstance(scene['caption'], str) or len(scene['caption']) > MAX_CAPTION:
            raise HarnessError(f"scene {scene['id']}: caption must be text of at most {MAX_CAPTION} characters")
    total = sum(scene['seconds'] for scene in scenes)
    if not MIN_SECONDS <= total <= MAX_SECONDS:
        raise HarnessError(f'scenes add up to {total:.1f} s; App Store previews are {MIN_SECONDS:.0f}–{MAX_SECONDS:.0f} s')
    return config


def _keys(value, expected, where):
    if not isinstance(value, dict) or set(value) != expected:
        found = sorted(value) if isinstance(value, dict) else type(value).__name__
        raise HarnessError(f'{where}: expected keys {sorted(expected)}, found {found}')


def load_markers(path):
    path = Path(path)
    if path.is_dir():
        manifest = json.loads((path / 'manifest.json').read_text())
        files = [path / item['exportedFileName']
                 for test in manifest for item in test['attachments']
                 if item['suggestedHumanReadableName'].startswith('preview-markers')]
        if len(files) != 1:
            raise HarnessError(f'expected one preview-markers attachment, found {len(files)}')
        path = files[0]
    data = json.loads(path.read_text())
    if data.get('clock') != 'unix' or not isinstance(data.get('marks'), dict):
        raise HarnessError('preview markers must be {"clock": "unix", "marks": {...}}')
    return path, data['marks']


def plan(config, marks, record_start, raw_seconds):
    """Where each scene comes from in the recording and where it goes in the preview."""
    cuts, at = [], 0.0
    for scene in config['scenes']:
        if scene['mark'] not in marks:
            raise HarnessError(f"scene {scene['id']}: the UI test set no mark '{scene['mark']}'")
        start = marks[scene['mark']] - record_start + scene['offset']
        end = start + scene['seconds']
        if start < 0 or end > raw_seconds:
            raise HarnessError(f"scene {scene['id']}: {start:.2f}–{end:.2f} s is outside the "
                               f'{raw_seconds:.2f} s recording')
        cuts.append({'id': scene['id'], 'source_start': round(start, 3), 'seconds': scene['seconds'],
                     'output_start': round(at, 3), 'caption': scene['caption']})
        at += scene['seconds']
    return cuts


def fit_filter(config):
    """Scale the recording to the preview width and crop the height evenly. No other change."""
    out = config['output']
    return (f"scale={out['width']}:-2:flags=lanczos,"
            f"crop={out['width']}:{out['height']}:0:(ih-{out['height']})/2,setsar=1")


def caption_filter(config, text_file):
    caption = config['caption']
    for path in (str(REPO / caption['font']), str(text_file)):
        if any(c in path for c in "':\\,;[]"):
            raise HarnessError(f'path not safe for an ffmpeg filter: {path}')
    return (f"drawtext=fontfile='{REPO / caption['font']}':textfile='{text_file}':expansion=none:"
            f"fontsize={caption['size']}:fontcolor=white:x=(w-text_w)/2:y={caption['y']}:"
            f"box=1:boxcolor=0x0E1116@0.75:boxborderw=22")


def caption_band(config):
    """Output rows the caption may cover; the frame match skips them."""
    caption = config['caption']
    return caption['y'] - 30, caption['y'] + caption['size'] * 2 + 30


def render_command(config, raw, cuts, text_files, output, music=None):
    total = sum(cut['seconds'] for cut in cuts)
    fps = config['output']['fps']
    parts = []
    for i, (cut, text) in enumerate(zip(cuts, text_files)):
        parts.append(f"[0:v]trim=start={cut['source_start']}:duration={cut['seconds']},setpts=PTS-STARTPTS,"
                     f"fps={fps},{fit_filter(config)},{caption_filter(config, text)}[v{i}]")
    parts.append(''.join(f'[v{i}]' for i in range(len(cuts))) + f'concat=n={len(cuts)}:v=1:a=0,format=yuv420p[v]')
    inputs = ['-i', str(raw)]
    if music:
        inputs += ['-i', str(music)]
        parts.append(f'[1:a]atrim=0:{total},asetpts=PTS-STARTPTS,apad=whole_dur={total},afade=t=out:st={total - 1.5}:d=1.5,'
                     'loudnorm=I=-14:TP=-1:LRA=11,aresample=48000,aformat=channel_layouts=stereo[a]')
    else:
        parts.append(f'anullsrc=channel_layout=stereo:sample_rate=48000,atrim=duration={total}[a]')
    return (['ffmpeg', '-y', '-v', 'error', *inputs, '-filter_complex', ';'.join(parts),
             '-map', '[v]', '-map', '[a]',
             '-c:v', 'libx264', '-profile:v', 'high', '-level', '4.0', '-pix_fmt', 'yuv420p', '-r', str(fps),
             '-b:v', '10M', '-maxrate', '12M', '-bufsize', '24M',
             '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-ac', '2',
             '-movflags', '+faststart', '-t', str(total), str(output)])


def mean_difference(a, b, width, skip_rows):
    if len(a) != len(b) or len(a) % width:
        raise HarnessError('frames differ in size')
    total = count = 0
    for row in range(0, len(a) // width, 2):  # every other row is plenty and twice as fast
        if skip_rows[0] <= row < skip_rows[1]:
            continue
        start = row * width
        total += sum(abs(x - y) for x, y in zip(a[start:start + width], b[start:start + width]))
        count += width
    return total / count


# ---------- ffmpeg ----------

def probe(path):
    result = subprocess.run(['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(path)],
                            check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def grey_frame(path, seconds, config, fit):
    vf = f'{fit_filter(config)},format=gray' if fit else 'format=gray'
    result = subprocess.run(['ffmpeg', '-v', 'error', '-ss', f'{seconds:.3f}', '-i', str(path), '-frames:v', '1',
                             '-vf', vf, '-f', 'rawvideo', '-'], check=True, capture_output=True)
    return result.stdout


def png_frame(path, seconds, target, config=None):
    vf = ['-vf', fit_filter(config)] if config else []
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-ss', f'{seconds:.3f}', '-i', str(path), '-frames:v', '1',
                    *vf, str(target)], check=True)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


# ---------- commands ----------

def prepare(args):
    config = load_config(args.scenes)
    markers_file, marks = load_markers(args.markers)
    record_start = float(Path(args.clock).read_text().strip())
    raw_seconds = float(probe(args.raw)['format']['duration'])
    raw_video = [s for s in probe(args.raw)['streams'] if s['codec_type'] == 'video']
    height = raw_video[0]['height'] * config['output']['width'] / raw_video[0]['width']
    if height < config['output']['height']:
        raise HarnessError('the recording is too short for the preview frame after scaling; record on a 6.9-inch simulator')
    cuts = plan(config, marks, record_start, raw_seconds)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / 'plan.json').write_text(json.dumps(cuts, indent=2) + '\n')
    return config, cuts, markers_file, out


def stills(args):
    config, cuts, _, out = prepare(args)
    folder = out / 'stills'
    folder.mkdir(exist_ok=True)
    for cut in cuts:
        for label, fraction in (('start', 0.02), ('mid', 0.5), ('end', 0.98)):
            target = folder / f"{cut['id']}-{label}.png"
            png_frame(args.raw, cut['source_start'] + cut['seconds'] * fraction, target, config)
            print(target)


def render(args):
    config, cuts, markers_file, out = prepare(args)
    if args.music:
        if not [s for s in probe(args.music)['streams'] if s['codec_type'] == 'audio']:
            raise HarnessError('--music has no audio stream')
    captions = out / 'captions'
    captions.mkdir(exist_ok=True)
    text_files = []
    for cut in cuts:
        text = captions / f"{cut['id']}.txt"
        text.write_text(cut['caption'])
        text_files.append(text.resolve())
    video = out / VIDEO_NAME
    subprocess.run(render_command(config, args.raw, cuts, text_files, video, args.music), check=True)
    png_frame(video, 0, out / 'poster-886x1920.png')
    version = subprocess.run(['ffmpeg', '-version'], capture_output=True, text=True).stdout.splitlines()[0]
    provenance = {
        'rule': 'Every video frame is a trim of the simulator recording below; only text captions are added.',
        'recording': {'file': Path(args.raw).name, 'sha256': sha256(args.raw), 'bytes': os.path.getsize(args.raw)},
        'markers_sha256': sha256(markers_file),
        'scenes_sha256': sha256(args.scenes),
        'music': {'file': Path(args.music).name, 'sha256': sha256(args.music)} if args.music else None,
        'commit': os.environ.get('GITHUB_SHA'),
        'ffmpeg': version,
        'cuts': cuts,
    }
    (out / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print(video)
    verify(args)


def verify(args):
    config = load_config(args.scenes)
    out = Path(args.out)
    video = out / VIDEO_NAME
    provenance = json.loads((out / 'provenance.json').read_text())
    if provenance['recording']['sha256'] != sha256(args.raw):
        raise HarnessError('the recording is not the one this preview was cut from')
    cuts = provenance['cuts']
    info = probe(video)
    streams = info['streams']
    video_streams = [s for s in streams if s['codec_type'] == 'video']
    audio_streams = [s for s in streams if s['codec_type'] == 'audio']
    problems = []
    if len(video_streams) != 1 or len(audio_streams) != 1 or len(streams) != 2:
        problems.append(f'expected one video and one audio stream, found {len(streams)} streams')
    else:
        v, a = video_streams[0], audio_streams[0]
        if (v['codec_name'], v['width'], v['height'], v['r_frame_rate']) != (
                'h264', config['output']['width'], config['output']['height'], '30/1'):
            problems.append(f"video is {v['codec_name']} {v['width']}x{v['height']} at {v['r_frame_rate']}")
        if (a['codec_name'], a['channels'], a['sample_rate']) != ('aac', 2, '48000'):
            problems.append(f"audio is {a['codec_name']}, {a['channels']} channels, {a['sample_rate']} Hz")
    duration = float(info['format']['duration'])
    planned = sum(cut['seconds'] for cut in cuts)
    if not MIN_SECONDS <= duration <= MAX_SECONDS or abs(duration - planned) > 0.25:
        problems.append(f'duration {duration:.2f} s, planned {planned:.2f} s')
    if os.path.getsize(video) >= MAX_BYTES:
        problems.append('file is 500 MB or larger')

    # Every scene must show the recording at the planned moment.
    width, band = config['output']['width'], caption_band(config)
    matches = []
    for cut in cuts:
        for fraction in (0.25, 0.75):
            ours = grey_frame(video, cut['output_start'] + cut['seconds'] * fraction, config, fit=False)
            source = grey_frame(args.raw, cut['source_start'] + cut['seconds'] * fraction, config, fit=True)
            difference = mean_difference(ours, source, width, band)
            matches.append({'scene': cut['id'], 'at': fraction, 'difference': round(difference, 2)})
            if difference > MATCH_LIMIT:
                problems.append(f"scene {cut['id']} at {fraction:.0%} differs from the recording ({difference:.1f})")
    report = {'video': VIDEO_NAME, 'bytes': os.path.getsize(video), 'seconds': round(duration, 3),
              'frame_matches': matches, 'problems': problems}
    (out / 'verify.json').write_text(json.dumps(report, indent=2) + '\n')
    if problems:
        raise HarnessError('preview failed verification:\n  ' + '\n  '.join(problems))
    print(f'verified: {duration:.2f} s, {len(matches)} frames match the recording')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('command', choices=['stills', 'render', 'verify', 'all'])
    parser.add_argument('--raw', required=True, help='simulator recording (raw.mov)')
    parser.add_argument('--clock', help='record-start.txt from record.sh')
    parser.add_argument('--markers', help='preview-markers JSON or xcresult attachment export')
    parser.add_argument('--scenes', default=str(SCENES))
    parser.add_argument('--music', help='optional licensed music; only its audio is used')
    parser.add_argument('--out', required=True)
    args = parser.parse_args(argv)
    if args.command != 'verify' and not (args.clock and args.markers):
        parser.error('--clock and --markers are required')
    try:
        if args.command in ('stills', 'all'):
            stills(args)
        if args.command in ('render', 'all'):
            render(args)
        if args.command == 'verify':
            verify(args)
    except (HarnessError, subprocess.CalledProcessError) as error:
        sys.exit(f'app preview: {error}')


if __name__ == '__main__':
    main()
