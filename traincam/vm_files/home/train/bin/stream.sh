#!/usr/bin/env bash
# Legacy VM helper script kept in sync with Ansible-managed publish.sh
set -euo pipefail
IFS=$'\n\t'

log(){ echo "$(date -Is) [traincam-stream] $*" >&2; }

CONFIG_FILE="${TRAINCAM_CONFIG:-/etc/traincam/stream.conf}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

: "${WIDTH:=1280}"
: "${HEIGHT:=720}"
: "${FPS:=24}"
: "${AWBGAINS:=1.00,1.12}"
: "${LATENCY_MODE:=ultra_plus}"
: "${KEYFRAME_INTERVAL:=$((FPS*2))}"
: "${EXTRA_OPTS:=}"

case "$LATENCY_MODE" in
  low)         KEYFRAME_INTERVAL=$(( FPS ));;
  ultra)       KEYFRAME_INTERVAL=$(( FPS / 2 ));;
  ultra_plus)  KEYFRAME_INTERVAL=$(( FPS / 4 ));;
esac
(( KEYFRAME_INTERVAL < 1 )) && KEYFRAME_INTERVAL=1

if [[ -n "${FORCE_KEYFRAME_INTERVAL:-}" ]]; then
  KEYFRAME_INTERVAL="${FORCE_KEYFRAME_INTERVAL}"
fi

RPI_CAM_BIN="${RPI_CAM_BIN:-$(command -v rpicam-vid || true)}"
if [[ -z "$RPI_CAM_BIN" ]]; then
  log "ERROR: rpicam-vid not found"; exit 127
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  log "ERROR: ffmpeg not available"; exit 127
fi

LOG_DIR="${LOG_DIR:-/var/log/traincam}"
mkdir -p "$LOG_DIR"

read -r -a EXTRA_ARRAY <<< "${EXTRA_OPTS}"

log "LATENCY_MODE=${LATENCY_MODE:-unset} KEYFRAME_INTERVAL=${KEYFRAME_INTERVAL}"

exec \
  "$RPI_CAM_BIN" -t 0 --inline \
    --width "$WIDTH" --height "$HEIGHT" --framerate "$FPS" \
    --awbgains "$AWBGAINS" --intra "$KEYFRAME_INTERVAL" "${EXTRA_ARRAY[@]}" -o - \
  | ffmpeg -hide_banner -loglevel error -fflags nobuffer -probesize 256 -analyzeduration 50000 \
    -f h264 -i - -c copy -rtsp_transport tcp -f rtsp rtsp://127.0.0.1:8554/traincam
