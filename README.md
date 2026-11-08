# aber-pi-holding-screen

Holding screen for the church ATEM Mini (Church of God of Prophecy, Aberdeen Street).

A Raspberry Pi on ATEM input 4 shows a full-screen image. Operators drag an image into a
shared folder on the church PC and it appears on input 4 within a couple of seconds. When
the folder is empty, the default image (church logo slide) is shown.

Full documentation is in the Plugged vault:
- `70-Church/Media and Streaming/Holding Screen Pi.md` (technical reference and rebuild)
- `70-Church/Runbooks/Holding Screen Operator Guide.md` (for operators)

## Files
| File | Installed to | Purpose |
|---|---|---|
| `install.sh` | (run once) | Sets everything up on a fresh Pi OS Lite |
| `holding-screen.sh` | `/opt/holding-screen/` | Watches the folder and drives mpv |
| `holding-screen.conf` | `/etc/holding-screen.conf` | Settings |
| `holding-screen.service` | `/etc/systemd/system/` | Starts it at boot, restarts on failure |
| `smb-share.conf` | appended to `/etc/samba/smb.conf` | The "Holding Screen" share |
| `default.jpg` | `/opt/holding-screen/` | Image shown when the share is empty |

## Quick install
On a Pi running Raspberry Pi OS Lite (32-bit for a Pi 2), with this folder copied or cloned
to the Pi:

```
cd aber-pi-holding-screen
sudo bash install.sh
sudo reboot
```

Then connect from Windows to `\\<pi address>\Holding Screen` as user `holdingscreen`.
