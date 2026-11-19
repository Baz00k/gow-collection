# Frame pacing diagnostics

Temporary tools for [#111](https://github.com/Baz00k/gow-collection/issues/111) (gamescope 3.16 double vblank under Wolf). Delete this directory when that issue is closed.

Both scripts run on the Wolf host during a live stream.

## Repeated frames

```bash
sudo ./measure.sh vsync-only 15
```

Pan the camera steadily for the whole capture. The script captures Wolf's video packets and decodes them, using parameter sets borrowed from a one-frame test encode, then counts frames identical to the previous one. With a healthy pipeline and the game at or above the stream rate, the count is near 0%. Output and `overlay.png` (MangoHud strip) go to `./frame-pacing-<label>/`.

It needs tcpdump, ffmpeg and python3 with numpy (`PYTHON=` picks the interpreter). Set `ENCODER` when Wolf's encoder differs from the default nvh265enc pipeline, and `WIDTH`/`HEIGHT` for streams other than 1080p.

## Vblank timer

```bash
./vblank-trace.sh 5
```

Traces gamescope's vblank timerfd from a throwaway container. A healthy nested session fires at the stream refresh rate with no double fires. With gamescope 3.16 under Wolf it shows about 64 fires/s at 60 Hz and several double fires per second.
