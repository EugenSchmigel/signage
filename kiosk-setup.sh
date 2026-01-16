#!/bin/bash

echo "=== Raspberry Pi 5 Digital Signage Setup – Optimiert ==="

USER="pi"
USER_HOME="/home/$USER"
CONFIG_FILE="$USER_HOME/kiosk.conf"
LOG_DIR="$USER_HOME/kiosk-logs"
LOG_FILE="$LOG_DIR/kiosk.log"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" | tee -a "$LOG_FILE"; }

log "Setup gestartet."

# ==========================
# Config-Datei
# ==========================
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<EOF
WEBSITE_URL=https://test.test.tech
FALLBACK_URL=file://$USER_HOME/offline/index.html
EOF
  log "Config-Datei erstellt."
fi
source "$CONFIG_FILE"

# ==========================
# System & Pakete
# ==========================
sudo apt update && sudo apt upgrade -y
sudo apt install --no-install-recommends -y xserver-xorg x11-xserver-utils xinit openbox
sudo apt install -y chromium unclutter xdotool curl
log "Pakete installiert."

# ==========================
# GPU / HDMI / Performance
# ==========================
sudo sed -i '/hdmi_force_hotplug/d;/hdmi_group/d;/hdmi_mode/d;/gpu_mem/d;/dtoverlay=vc4-kms-v3d/d' /boot/config.txt
sudo tee -a /boot/config.txt >/dev/null <<EOF
hdmi_force_hotplug=1
hdmi_group=1
hdmi_mode=16
gpu_mem=256
dtoverlay=vc4-kms-v3d
EOF
log "HDMI + GPU konfiguriert."

# ==========================
# Xorg Treiber (modesetting)
# ==========================
sudo rm -f /etc/X11/xorg.conf.d/99-pi.conf
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/10-modesetting.conf >/dev/null <<EOF
Section "Device"
    Identifier "Builtin Graphics"
    Driver "modesetting"
EndSection
EOF
log "Xorg auf modesetting gesetzt."

# ==========================
# Energiesparfunktionen
# ==========================
sudo mkdir -p /etc/xdg/openbox
sudo tee /etc/xdg/openbox/autostart >/dev/null <<EOF
@xset s off
@xset -dpms
@xset s noblank
EOF

# ==========================
# WLAN Power Saving
# ==========================
sudo tee /etc/network/if-up.d/wlan-reconnect >/dev/null <<EOF
#!/bin/bash
iwconfig wlan0 power off || true
EOF
sudo chmod +x /etc/network/if-up.d/wlan-reconnect

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
  --use-gl=egl --enable-features=VaapiVideoDecoder \
  --ignore-gpu-blocklist --enable-zero-copy \
  --disable-dev-shm-usage --disk-cache-size=104857600 \
  --force-dark-mode --no-first-run --no-default-browser-check
EOF
chmod +x "$USER_HOME/start-chromium.sh"

# ==========================
# Xinitrc
# ==========================
cat > "$USER_HOME/.xinitrc" <<EOF
#!/bin/bash
openbox-session &
unclutter &
$USER_HOME/start-chromium.sh
EOF
chmod +x "$USER_HOME/.xinitrc"

# ==========================
# systemd Service statt Bash-Profile
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
log "systemd Kiosk-Service aktiviert."

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
# Reboot-Cronjob
# ==========================
(sudo crontab -l 2>/dev/null; echo "0 4 * * * /sbin/reboot") | sudo crontab -

log "Setup abgeschlossen. Bitte neu starten."
echo "=== Installation abgeschlossen ==="
