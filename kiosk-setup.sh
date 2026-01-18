\#!/bin/bash

echo "=== Raspberry Pi Digital Signage – Professional Setup ==="

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
WEBSITE_URL=<https://test.test.tech>
FALLBACK_URL=file://$USER_HOME/offline/index.html
EOF

# ==========================

# System & Pakete

# ==========================

sudo apt update && sudo apt upgrade -y
sudo apt install -y --no-install-recommends xserver-xorg x11-xserver-utils xinit openbox
sudo apt install -y chromium unclutter xdotool curl jq
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

# Mauszeiger ausblenden

# ==========================

sudo tee /etc/xdg/openbox/autostart >/dev/null <<EOF
@xset s off
@xset -dpms
@xset s noblank
@unclutter -idle 0
EOF

# ==========================

# WLAN Stabilisierung

# ==========================

sudo tee /etc/network/if-up.d/wlan-stabilize >/dev/null <<EOF
\#!/bin/bash
iwconfig wlan0 power off || true
EOF
sudo chmod +x /etc/network/if-up.d/wlan-stabilize

# ==========================

# Chromium Startscript

# ==========================

cat > "$USER_HOME/start-chromium.sh" <<EOF
\#!/bin/bash
source "$CONFIG_FILE"
export DISPLAY=:0
chromium --kiosk "$WEBSITE_URL" \
\--noerrdialogs --disable-infobars --disable-session-crashed-bubble \
\--autoplay-policy=no-user-gesture-required \
\--use-gl=egl --enable-features=VaapiVideoDecoder \
\--ignore-gpu-blocklist --enable-zero-copy \
\--disable-dev-shm-usage --disk-cache-size=104857600 \
\--force-dark-mode --no-first-run --no-default-browser-check
EOF
chmod +x "$USER_HOME/start-chromium.sh"

# ==========================

# Xinitrc

# ==========================

cat > "$USER_HOME/.xinitrc" <<EOF
\#!/bin/bash
openbox-session &
unclutter &
$USER_HOME/start-chromium.sh
EOF
chmod +x "$USER_HOME/.xinitrc"

# ==========================

# Autologin ohne Desktop

# ==========================

sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pi --noclear %I $TERM
EOF

# ==========================

# systemd Kiosk-Service

# ==========================

sudo tee /etc/systemd/system/kiosk.service >/dev/null <<EOF
[Unit]
Description=Chromium Kiosk
After=graphical.target network-online.target
Wants=network-online.target

[Service]
User=$USER
Environment=DISPLAY=:0
ExecStart=$USER_HOME/start-chromium.sh
Restart=always

[Install]
WantedBy=graphical.target
EOF
sudo systemctl enable kiosk.service

# ==========================

# Browser-Watchdog

# ==========================

sudo tee /etc/systemd/system/browser-watchdog.service >/dev/null <<EOF
[Unit]
Description=Browser Watchdog
After=network-online.target

[Service]
User=$USER
ExecStart=/bin/bash -c 'while true; do pgrep chromium || startx; sleep 30; done'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable browser-watchdog.service

# ==========================

# Netzwerk-Watchdog

# ==========================

sudo tee /etc/systemd/system/network-watchdog.service >/dev/null <<EOF
[Unit]
Description=Network Watchdog

[Service]
User=$USER
ExecStart=/bin/bash -c '
while true; do
if ping -c1 8.8.8.8 >/dev/null 2>&1; then
echo "Online" > $LOG_FILE
else
chromium --kiosk "$FALLBACK_URL"
fi
sleep 60
done'
Restart=always

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable network-watchdog.service

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

(sudo crontab -l 2>/dev/null; echo "0 4  * /sbin/reboot") | sudo crontab -

log "Setup abgeschlossen. Bitte neu starten."
