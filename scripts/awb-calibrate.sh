#!/usr/bin/env bash
# Measure white balance error against a neutral target and print corrected gains.
#
# WHY THIS EXISTS
# ---------------
# traincam_awb_gains in group_vars is a pair of fixed ColourGains [RED,BLUE].
# Fixed gains are correct for exactly one light source. The value in the repo
# was measured indoors at home; under different lighting it is wrong, and the
# error shows up as a colour cast (magenta at the layout, measured 2026-08-01).
#
# You cannot calibrate this from a still. Per group_vars/traincam.yml:39-43 the
# AWB algorithm converges differently in the video pipeline than in the stills
# pipeline, so this script samples the LIVE RTSP stream - the same pixels the
# viewer sees.
#
# You also cannot calibrate it off the scene. A model railroad is mostly green
# foliage and brown earth; any grey-world estimate is dragged toward magenta by
# the greenery. That is why this asks for a physical neutral target.
#
# USAGE
#   Put something neutral in front of the lens, filling the middle of frame:
#   white printer paper, a grey card, or the white side of a business card.
#   Light it the same as the scene - do not shade it or aim a torch at it.
#
#     ./awb-calibrate.sh                 # sample and print suggested gains
#     ./awb-calibrate.sh --check         # verify the maths, no camera needed
#
# Run it on the camera (needs ffmpeg and the local RTSP feed), e.g.
#     ssh train@traincam1.local 'bash -s' < scripts/awb-calibrate.sh
set -euo pipefail

RTSP="${RTSP:-rtsp://127.0.0.1:8554/traincam}"
CONF="${CONF:-/etc/traincam/stream.conf}"
SAMPLES="${SAMPLES:-5}"

# Correct a gain pair so a measured patch becomes neutral.
# ColourGains scale red and blue relative to green, so the correction is just
# the ratio green/channel. Echoed as "R B".
correct_gains() {
    awk -v r="$1" -v g="$2" -v b="$3" -v rg="$4" -v bg="$5" 'BEGIN {
        if (r <= 0 || g <= 0 || b <= 0) { print "ERR"; exit 1 }
        printf "%.3f %.3f", rg * (g / r), bg * (g / b)
    }'
}

# True when a patch is too far off neutral to plausibly be a neutral target.
# Kept as a function so --check can exercise it without a camera.
is_implausible() {
    awk -v r="$1" -v g="$2" -v b="$3" 'BEGIN{
        rr=r/g; bb=b/g
        exit !(rr<0.8 || rr>1.25 || bb<0.8 || bb>1.25) }'
}

# ponytail: one self-check, because the maths is the only non-obvious part.
if [ "${1:-}" = "--check" ]; then
    # Already neutral -> gains unchanged.
    [ "$(correct_gains 100 100 100 0.99 2.23)" = "0.990 2.230" ] \
        || { echo "FAIL: neutral patch should not move the gains"; exit 1; }
    # Magenta patch (red and blue high) -> both gains must come DOWN.
    read -r nr nb <<<"$(correct_gains 120 100 110 0.99 2.23)"
    awk -v a="$nr" 'BEGIN{exit !(a < 0.99)}' || { echo "FAIL: red gain should drop"; exit 1; }
    awk -v a="$nb" 'BEGIN{exit !(a < 2.23)}' || { echo "FAIL: blue gain should drop"; exit 1; }
    # Green-cast patch -> gains must go UP, i.e. the sign is not hardcoded.
    read -r nr2 _ <<<"$(correct_gains 80 100 90 0.99 2.23)"
    awk -v a="$nr2" 'BEGIN{exit !(a > 0.99)}' || { echo "FAIL: red gain should rise"; exit 1; }
    # The guard: a plausible near-neutral card passes, foliage does not.
    is_implausible 100 100 100 && { echo "FAIL: neutral patch rejected"; exit 1; }
    is_implausible 108 100 94  && { echo "FAIL: realistic card rejected"; exit 1; }
    is_implausible 100 129 95  || { echo "FAIL: foliage should be rejected"; exit 1; }
    echo "self-check OK"
    exit 0
fi

command -v ffmpeg >/dev/null || { echo "ffmpeg not found - run this on the camera" >&2; exit 1; }

cur_r=""; cur_b=""
if [ -r "$CONF" ]; then
    line=$(grep -E '^[[:space:]]*AWB_GAINS=' "$CONF" 2>/dev/null | tail -1 || true)
    gains=${line#*=}; gains=${gains//\"/}; gains=${gains//\'/}
    case "$gains" in *,*) cur_r=${gains%%,*}; cur_b=${gains##*,} ;; esac
fi
[ -n "$cur_r" ] || { cur_r=1.0; cur_b=1.0; echo "note: no AWB_GAINS in $CONF, reporting absolute ratios"; }

echo "sampling $SAMPLES frames from $RTSP ..."
sum_r=0; sum_g=0; sum_b=0; got=0
for _ in $(seq "$SAMPLES"); do
    # Crop the middle fifth, average it to a single pixel, read the RGB bytes.
    # -nostdin matters: this script is often piped in via `ssh 'bash -s'`, and
    # ffmpeg would otherwise consume the rest of the script from stdin.
    px=$(ffmpeg -nostdin -loglevel error -rtsp_transport tcp -i "$RTSP" -frames:v 1 \
            -vf "crop=iw/5:ih/5,scale=1:1" -f rawvideo -pix_fmt rgb24 - 2>/dev/null \
         | od -An -tu1 | tr -s ' ' | sed 's/^ //') || true
    # shellcheck disable=SC2086  # deliberate: split the three RGB bytes
    set -- $px
    [ $# -ge 3 ] || continue
    sum_r=$((sum_r + $1)); sum_g=$((sum_g + $2)); sum_b=$((sum_b + $3)); got=$((got + 1))
done
[ "$got" -gt 0 ] || { echo "ERROR: no frames captured - is the stream up?" >&2; exit 1; }

R=$((sum_r / got)); G=$((sum_g / got)); B=$((sum_b / got))
echo "target patch over $got frames:  R=$R  G=$G  B=$B"

if [ "$G" -lt 25 ] || [ "$R" -lt 25 ] || [ "$B" -lt 25 ]; then
    echo "ERROR: patch too dark to trust - light it like the scene." >&2; exit 1
fi
if [ "$R" -gt 245 ] || [ "$G" -gt 245 ] || [ "$B" -gt 245 ]; then
    echo "ERROR: patch is clipping - a blown highlight carries no colour." >&2; exit 1
fi

awk -v r="$R" -v g="$G" -v b="$B" 'BEGIN{
    printf "cast: R/G=%.3f  B/G=%.3f  (1.000 = neutral)\n", r/g, b/g }'
read -r new_r new_b <<<"$(correct_gains "$R" "$G" "$B" "$cur_r" "$cur_b")"

# A real neutral target photographed under fixed gains is usually within ~20%
# of neutral. A bigger error almost always means the lens is not looking at the
# target at all - a model railroad centre-frame is foliage, which reads green
# and would push these gains hard toward magenta. Applying that silently is the
# worst outcome, so refuse rather than warn.
if is_implausible "$R" "$G" "$B"; then
    echo
    echo "REFUSING to suggest gains: the patch is $(awk -v r="$R" -v g="$G" 'BEGIN{printf "%.0f%%", (r/g-1)*100}') red / $(awk -v b="$B" -v g="$G" 'BEGIN{printf "%.0f%%", (b/g-1)*100}') blue off neutral." >&2
    echo "That is too far off for a neutral target. Most likely the lens is not" >&2
    echo "actually filled by the card - centre-frame foliage reads like this." >&2
    echo "Fill the middle of the frame with the card and re-run." >&2
    echo "(would have said: \"$new_r,$new_b\" - do not use it)" >&2
    exit 2
fi

echo "current traincam_awb_gains: \"$cur_r,$cur_b\""
echo "suggested traincam_awb_gains: \"$new_r,$new_b\""
echo
echo "Set that in group_vars/traincam.yml, redeploy, then re-run to confirm"
echo "the cast has moved to ~1.000. Re-measure if the venue lighting changes."
