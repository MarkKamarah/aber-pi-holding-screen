#!/usr/bin/env bash
# Installs the holding screen on a fresh Raspberry Pi OS Lite.
# Usage (from this folder on the Pi):  sudo bash install.sh
# Safe to run again; it skips anything already done.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run with sudo:  sudo bash install.sh"
    exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
SVC_USER=holdingscreen

echo "== Installing packages"
apt-get update
apt-get install -y samba inotify-tools mpv socat

echo "== Creating service user and folders"
if ! id "$SVC_USER" >/dev/null 2>&1; then
    useradd --system --home-dir /srv/holding-screen --no-create-home \
        --shell /usr/sbin/nologin "$SVC_USER"
fi
usermod -aG video,render "$SVC_USER"
install -d -o "$SVC_USER" -g "$SVC_USER" -m 0775 /srv/holding-screen
install -d -o "$SVC_USER" -g "$SVC_USER" -m 0775 /srv/holding-screen/images
install -d -m 0755 /opt/holding-screen

echo "== Installing scripts and settings"
install -m 0755 "$HERE/holding-screen.sh" /opt/holding-screen/holding-screen.sh
if [ ! -f /etc/holding-screen.conf ]; then
    install -m 0644 "$HERE/holding-screen.conf" /etc/holding-screen.conf
else
    echo "   /etc/holding-screen.conf already exists, leaving it as is"
fi
# Default image: default.png, default.jpg or default.jpeg in this folder.
DEFAULT_FOUND=no
for ext in png jpg jpeg; do
    if [ -f "$HERE/default.$ext" ]; then
        install -m 0644 "$HERE/default.$ext" "/opt/holding-screen/default.$ext"
        sed -i "s|^DEFAULT_IMAGE=.*|DEFAULT_IMAGE=/opt/holding-screen/default.$ext|" /etc/holding-screen.conf
        echo "   default image: /opt/holding-screen/default.$ext"
        DEFAULT_FOUND=yes
        break
    fi
done
if [ "$DEFAULT_FOUND" = "no" ]; then
    echo "   NOTE: no default image in this folder. The screen shows black when the"
    echo "         share is empty until one is added (see the runbook)."
fi
install -m 0644 "$HERE/holding-screen.service" /etc/systemd/system/holding-screen.service

echo "== Configuring the Samba share"
if ! grep -q '^\[Holding Screen\]' /etc/samba/smb.conf; then
    cp -n /etc/samba/smb.conf /etc/samba/smb.conf.orig
    cat "$HERE/smb-share.conf" >> /etc/samba/smb.conf
fi
testparm -s >/dev/null
systemctl restart smbd

if ! pdbedit -L 2>/dev/null | grep -q "^$SVC_USER:"; then
    echo
    echo "Set the password the church PC will use to connect to the share"
    echo "(username: $SVC_USER)"
    smbpasswd -a "$SVC_USER"
fi

echo "== Configuring the display at boot"
CMDLINE=/boot/firmware/cmdline.txt
cp -n "$CMDLINE" "$CMDLINE.orig"
add_cmdline() {
    local key="$1" value="$2"
    if ! grep -qE "(^| )${key}=" "$CMDLINE"; then
        sed -i "1 s|\$| ${key}=${value}|" "$CMDLINE"
    fi
}
add_cmdline consoleblank 0                      # never blank the screen
add_cmdline vt.global_cursor_default 0          # hide the text cursor
add_cmdline video "HDMI-A-1:1920x1080@60D"      # always output 1080p, even if the ATEM is off at boot

# The login prompt on screen 1 is not needed; SSH still works.
systemctl mask getty@tty1.service

echo "== Starting the holding screen"
systemctl daemon-reload
systemctl enable holding-screen.service
systemctl restart holding-screen.service

echo
echo "Done. Reboot once so the display settings take effect:  sudo reboot"
echo "Share:  \\\\$(hostname)\\Holding Screen   (or \\\\<ip address>\\Holding Screen)"
