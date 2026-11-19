#!/usr/bin/env bash
# Measure repeated frames in Wolf's encoded video output.
#
# Run on the Wolf host as root while a stream is live and the camera pans steadily:
#   sudo ./measure.sh <label> [seconds]
#
# Needs tcpdump, ffmpeg, python3 with numpy (set PYTHON to pick another interpreter)
# and docker access to the Wolf container. Results go to ./frame-pacing-<label>/.
set -euo pipefail

LABEL="${1:?usage: measure.sh <label> [seconds]}"
SECONDS_TO_CAPTURE="${2:-15}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${PYTHON:-python3}"
WIDTH="${WIDTH:-1920}"
HEIGHT="${HEIGHT:-1080}"
VIDEO_PORT="${VIDEO_PORT:-48100}"
IFACE="${IFACE:-$(ip -4 route show default | awk '{print $5; exit}')}"
WOLF_CONTAINER="${WOLF_CONTAINER:-$(docker ps --format '{{.Names}}\t{{.Image}}' | awk -F'\t' '$2 ~ /games-on-whales\/wolf(:|@)/ {print $1; exit}')}"
# Must match the encoder settings in Wolf's config, or the borrowed parameter sets won't decode.
ENCODER="${ENCODER:-nvh265enc gop-size=-1 bitrate=20000 aud=false rc-mode=cbr zerolatency=true preset=p1 tune=ultra-low-latency multi-pass=two-pass-quarter ! video/x-h265,stream-format=byte-stream}"

OUT="$(pwd)/frame-pacing-${LABEL}"
mkdir -p "${OUT}"
cd "${OUT}"

echo "capturing ${SECONDS_TO_CAPTURE}s of udp src port ${VIDEO_PORT} on ${IFACE}"
rm -f capture.pcap
timeout "${SECONDS_TO_CAPTURE}" tcpdump -Z root -i "${IFACE}" -n -w capture.pcap "udp and src port ${VIDEO_PORT}" 2>/dev/null || true

# Mid-stream captures carry no keyframe or parameter sets, so encode one test frame
# with the same encoder and borrow its VPS/SPS/PPS.
docker exec "${WOLF_CONTAINER:?Wolf container not found; set WOLF_CONTAINER}" sh -c \
    "gst-launch-1.0 -q videotestsrc num-buffers=1 ! video/x-raw,width=${WIDTH},height=${HEIGHT},framerate=60/1 ! cudaupload ! cudaconvertscale ! 'video/x-raw(memory:CUDAMemory),format=NV12' ! ${ENCODER} ! filesink location=/tmp/frame-pacing-ps.bin" >/dev/null 2>&1
docker cp "${WOLF_CONTAINER}:/tmp/frame-pacing-ps.bin" testframe.bin >/dev/null
"${PYTHON}" - testframe.bin param-sets.bin <<'EOF'
import re, sys
data = open(sys.argv[1], 'rb').read()
starts = [m.start() for m in re.finditer(b'\x00\x00\x01', data)]
out = b''
for i, s in enumerate(starts):
    nal = data[s + 3:starts[i + 1] if i + 1 < len(starts) else len(data)].rstrip(b'\x00')
    if (nal[0] >> 1) & 0x3f in (32, 33, 34):
        out += b'\x00\x00\x00\x01' + nal
open(sys.argv[2], 'wb').write(out)
EOF

"${PYTHON}" "${HERE}/reassemble.py" capture.pcap stream.bin
cat param-sets.bin stream.bin > decodable.hevc

ffmpeg -nostdin -y -hide_banner -loglevel quiet -flags +output_corrupt -err_detect ignore_err \
    -f hevc -i decodable.hevc -vf "scale=480:270,format=gray" -f rawvideo -fps_mode passthrough frames.gray
# Overlay strip from the middle of the capture, to read MangoHud's FPS.
ffmpeg -nostdin -y -hide_banner -loglevel quiet -flags +output_corrupt \
    -f hevc -i decodable.hevc -vf "select='eq(n\,$((SECONDS_TO_CAPTURE * 30)))',crop=700:40:0:0" -frames:v 1 overlay.png

"${PYTHON}" "${HERE}/repeats.py" frames.gray | tee result.txt
echo "overlay: ${OUT}/overlay.png"
