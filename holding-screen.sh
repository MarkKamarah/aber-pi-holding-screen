#!/usr/bin/env bash
# Holding screen: shows the newest image in the shared folder full screen on HDMI.
# If the folder is empty, shows the default image instead.
# Runs as a systemd service (holding-screen.service). Logs: journalctl -u holding-screen

set -u

CONF=/etc/holding-screen.conf
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

IMAGE_DIR="${IMAGE_DIR:-/srv/holding-screen/images}"
DEFAULT_IMAGE="${DEFAULT_IMAGE:-/opt/holding-screen/default.png}"
KEEP_ONLY_LATEST="${KEEP_ONLY_LATEST:-yes}"
PREVIOUS_DIR="${PREVIOUS_DIR:-$IMAGE_DIR/Previous images}"
MPV_VO="${MPV_VO:-drm}"
RESCAN_SECONDS="${RESCAN_SECONDS:-30}"
SOCKET="${RUNTIME_DIRECTORY:-/tmp/holding-screen}/mpv.sock"

CURRENT=""

log() { echo "holding-screen: $*"; }

# Newest image in the top level of the share, by change time (ctime).
# ctime is used rather than mtime because Windows keeps the original
# "modified" date when copying, so mtime does not reflect when it was dropped in.
newest_image() {
    find "$IMAGE_DIR" -maxdepth 1 -type f ! -name '.*' \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
           -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.webp' \) \
        -printf '%C@\t%p\n' 2>/dev/null | sort -n | tail -n 1 | cut -f2-
}

# Move every other image into "Previous images" so only the newest stays in the folder.
archive_others() {
    local keep="$1" f
    mkdir -p "$PREVIOUS_DIR"
    find "$IMAGE_DIR" -maxdepth 1 -type f ! -name '.*' \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
           -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.webp' \) -print0 |
    while IFS= read -r -d '' f; do
        [ "$f" = "$keep" ] && continue
        mv -f -- "$f" "$PREVIOUS_DIR/" && log "moved to Previous images: $(basename "$f")"
    done
}

mpv_cmd() {
    printf '%s\n' "$1" | socat - UNIX-CONNECT:"$SOCKET" >/dev/null 2>&1
}

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

refresh() {
    local img target key
    img="$(newest_image)"
    if [ -n "$img" ]; then
        [ "$KEEP_ONLY_LATEST" = "yes" ] && archive_others "$img"
        target="$img"
    else
        target="$DEFAULT_IMAGE"
    fi

    key="$target|$(stat -c %Z -- "$target" 2>/dev/null)"
    [ "$key" = "$CURRENT" ] && return 0

    if [ -f "$target" ]; then
        mpv_cmd "{\"command\":[\"loadfile\",\"$(json_escape "$target")\",\"replace\"]}" &&
            { log "showing: $target"; CURRENT="$key"; }
    else
        log "no image to show and default image missing ($DEFAULT_IMAGE), showing black"
        mpv_cmd '{"command":["stop"]}' && CURRENT="$key"
    fi
}

watch_loop() {
    refresh
    while true; do
        read -r -t "$RESCAN_SECONDS" _
        rc=$?
        if [ "$rc" -eq 0 ]; then
            # Wait for a second of quiet so a burst of events is handled once.
            while read -r -t 1 _; do :; done
        elif [ "$rc" -le 128 ]; then
            log "folder watcher stopped"
            return 1
        fi
        refresh
    done < <(inotifywait -m -q -e close_write,moved_to,moved_from,delete "$IMAGE_DIR")
}

mkdir -p "$(dirname "$SOCKET")"
rm -f "$SOCKET"

mpv --vo="$MPV_VO" \
    --idle=yes --force-window=yes \
    --image-display-duration=inf --keep-open=yes \
    --audio=no --osc=no --osd-level=0 \
    --no-input-default-bindings --input-terminal=no \
    --cursor-autohide=always --really-quiet \
    --input-ipc-server="$SOCKET" &
MPV_PID=$!

for _ in $(seq 1 50); do
    [ -S "$SOCKET" ] && break
    sleep 0.2
done
if [ ! -S "$SOCKET" ]; then
    log "mpv did not start"
    kill "$MPV_PID" 2>/dev/null
    exit 1
fi

watch_loop &
WATCH_PID=$!

# If either mpv or the watcher stops, stop both so systemd restarts everything cleanly.
wait -n "$MPV_PID" "$WATCH_PID"
log "a component exited, restarting"
kill "$MPV_PID" "$WATCH_PID" 2>/dev/null
exit 1
