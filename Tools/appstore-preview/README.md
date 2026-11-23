# App Store preview video

The preview is cut from a screen recording of the real app. Nothing in it is drawn, mocked up or
imported: every frame is a trim of the simulator recording, with only a text caption added.

## How a preview is made

1. **Record (macOS CI).** Run the `ios-build` workflow with `evidence=apppreview`. It sets the
   9:41 status bar and dark appearance on the 6.9-inch simulator. `record.sh` then records the
   screen while `RoadPrintUITests/AppStorePreviewTests` drives the app: it records the replayed I-80
   trip, opens the trip summary, shares it as a video card, then shows My map and its year and road
   filters. The test marks when each scene starts.
2. **Review stills.** `render.py stills` writes start, middle and end frames of every scene from the
   recording to `out/stills/`. Check them before using the video.
3. **Render.** `render.py render` trims each scene out of the recording, scales it to 886×1920 at
   30 fps, adds the caption and a silent (or music) stereo track, and writes the `.mp4`, a poster
   PNG and `provenance.json` (recording hash and the source time of every cut).
4. **Verify.** `render.py verify` checks the App Store format (H.264, 886×1920, 30 fps, AAC stereo
   48 kHz, 15–30 s, under 500 MB). It also compares two frames of every scene with the same moments
   of the recording and fails if any differs outside the caption band.

The workflow runs steps 2–4 (`render.py all`) and uploads `app-preview`: the video, poster,
stills, provenance, verify report and the raw recording.

## Re-cut without re-recording

Download the `app-preview` artifact and the `ios-apppreview-evidence` artifact (it holds the
markers). Edit `scenes.json` (timings and captions only), then run, with ffmpeg installed:

    python3 Tools/appstore-preview/render.py all --raw raw.mov --clock record-start.txt \
      --markers RoadPrint --out out [--music licensed-track.m4a]

`scenes.json` accepts only scene timings and caption text. Any other key, such as an image path,
is rejected. Music adds audio only.

## Changing what is filmed

Edit the choreography in `AppStorePreviewTests` and the matching `mark` names in `scenes.json`.
The app runs with `-RPAppStoreScreenshots` (seeded Western US trip history, in memory) and
`-RPAppStorePreview`, which lets the share card animate instead of freezing it for stills.
