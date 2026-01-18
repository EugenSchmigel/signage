#!/bin/bash

echo "=== Raspberry Pi Digital Signage – Systemd Kiosk Setup (Repariert) ==="

USER="pi"
USER_HOME="/home/$USER"
CONFIG_FILE="$USER_HOME/kiosk.conf"
LOG_DIR="$USER_HOME/kiosk-logs"
LOG_FILE="$LOG_DIR/kiosk.log"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" | tee -a "$LOG_FILE"; }

# ==========================
# Config-Datei
# ==========================

cat > "$CONFIG_FILE" <<EOF
WEBSITE_URL=https://test.test.tech
FALLBACK_URL=file://$USER_HOME/offline/index.html
EOF

# ==========================
# System & Pakete
# ==========================

sudo apt update && sudo apt upgrade -y
sudo apt install -y --no-install-recommends xserver-xorg x11-xserver-utils xinit openbox
sudo apt install -y chromium chromium-browser unclutter xdotool curl jq
log "Pakete installiert."

# ==========================
# HDMI Fixes
# ==========================

sudo sed -i '/dtoverlay=/d;/gpu_mem=/d;/hdmi_force_hotplug=/d/' /boot/config.txt
sudo tee -a /boot/config.txt >/dev/null <<EOF
dtoverlay=vc4-fkms-v3d
gpu_mem=256
hdmi_force_hotplug=1
EOF

# ==========================
# WLAN Stabilisierung
# ==========================

sudo tee /etc/network/if-up.d/wlan-stabilize >/dev/null <<EOF
#!/bin/bash
iwconfig wlan0 power off || true
EOF
sudo chmod +x /etc/network/if-up.d/wlan-stabilize

# ==========================
# Openbox Autostart
# ==========================

sudo tee /etc/xdg/openbox/autostart >/dev/null <<EOF
@xset s off
@xset -dpms
@xset s noblank
@unclutter -idle 0
EOF

# ==========================
# Chromium Startscript
# ==========================

cat > "$USER_HOME/start-chromium.sh" <<EOF
#!/bin/bash
source "$CONFIG_FILE"
export DISPLAY=:0

chromium --kiosk "\$WEBSITE_URL" \
  --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required \
  --disable-dev-shm-usage --no-first-run --no-default-browser-check \
  --force-dark-mode
EOF

chmod +x "$USER_HOME/start-chromium.sh"

# ==========================
# X11 Startscript
# ==========================

cat > "$USER_HOME/start-x.sh" <<EOF
#!/bin/bash
export DISPLAY=:0
startx /usr/bin/openbox-session
EOF

chmod +x "$USER_HOME/start-x.sh"

# ==========================
# systemd: X11 Service
# ==========================

sudo tee /etc/systemd/system/x11.service >/dev/null <<EOF
[Unit]
Description=Start X11 Server
After=systemd-user-sessions.service

[Service]
User=pi
Environment=DISPLAY=:0
ExecStart=/home/pi/start-x.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable x11.service

# ==========================
# systemd: Chromium Service
# ==========================

sudo tee /etc/systemd/system/kiosk.service >/dev/null <<EOF
[Unit]
Description=Chromium Kiosk
After=x11.service network-online.target
Wants=network-online.target

[Service]
User=pi
Environment=DISPLAY=:0
ExecStart=/home/pi/start-chromium.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kiosk.service

# ==========================
# Offline-Fallback
# ==========================

mkdir -p "$USER_HOME/offline"
cat > "$USER_HOME/offline/index.html" <<EOF
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Offline</title>
<style>body{background:black;color:white;font-size:40px;text-align:center;padding-top:20%;}</style>
</head><body>Offline – Verbindung wird wiederhergestellt…</body></html>
EOF

# ==========================
# Logrotate
# ==========================

sudo tee /etc/logrotate.d/kiosk >/dev/null <<EOF
$LOG_FILE {
daily
rotate 7
compress
missingok
notifempty
create 644 $USER $USER
}
EOF

# ==========================
# Täglicher Reboot
# ==========================

(sudo crontab -l 2>/dev/null; echo "0 4 * * * /sbin/reboot") | sudo crontab -

log "Setup abgeschlossen. Bitte neu starten."
