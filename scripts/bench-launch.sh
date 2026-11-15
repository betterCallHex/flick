#!/usr/bin/env bash
set -euo pipefail

app="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
budget_ms="${BUDGET_MS:-1000}"
runs="${RUNS:-5}"
media_dir="$(pwd)/.bench"
probe="$media_dir/first-frame"
mkdir -p "$media_dir"

now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }

make_media() {
  local name="$1"; shift
  [[ -f "$media_dir/$name" ]] || ffmpeg -y -loglevel error "$@" "$media_dir/$name"
}

make_media h264-1080p.mp4 -f lavfi -i testsrc2=size=1920x1080:rate=30:duration=30 -f lavfi -i sine=duration=30 \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -shortest
make_media hevc-4k.mkv -f lavfi -i testsrc2=size=3840x2160:rate=24:duration=10 -f lavfi -i sine=duration=10 \
  -c:v hevc_videotoolbox -b:v 20M -c:a libopus -shortest
make_media vp9-720p.webm -f lavfi -i testsrc2=size=1280x720:rate=30:duration=5 -f lavfi -i sine=duration=5 \
  -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 2M -c:a libopus -shortest

launch_ms() {
  pkill -x Flick 2>/dev/null || true
  rm -f "$probe"
  local started
  started=$(now_ms)
  open -n -a "$app" --env "FLICK_FIRST_FRAME_FILE=$probe" "$1"
  for _ in $(seq 500); do [[ -s "$probe" ]] && break; sleep 0.01; done
  if [[ ! -s "$probe" ]]; then
    pkill -x Flick 2>/dev/null || true
    echo "timeout"
    return
  fi
  echo $(( $(cat "$probe") - started ))
}

echo "first launch of this build (one-time signature check, not budgeted): $(launch_ms "$media_dir/h264-1080p.mp4") ms"

worst=0
failed=0
for media in "$media_dir"/*.{mp4,mkv,webm}; do
  timings=()
  for _ in $(seq "$runs"); do
    elapsed=$(launch_ms "$media")
    if [[ "$elapsed" == timeout ]]; then
      echo "FAIL $(basename "$media"): no visible frame within 5s"
      failed=1
      continue
    fi
    timings+=("$elapsed")
    (( elapsed > worst )) && worst=$elapsed
  done
  printf '%-16s %s ms\n' "$(basename "$media")" "${timings[*]}"
done

echo "slowest launch-to-first-frame: ${worst} ms (budget ${budget_ms} ms)"
if (( failed || worst > budget_ms )); then
  echo "FAIL: over budget"
  exit 1
fi
echo "PASS"
