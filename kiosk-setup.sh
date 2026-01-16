#!/bin/bash

echo "=== Raspberry Pi 5 Digital Signage Setup – Voll optimiert ==="

USER="pi"
USER_HOME="/home/$USER"
CONFIG_FILE="$USER_HOME/kiosk.conf"
LOG_DIR="$USER_HOME/kiosk-logs"
LOG_FILE="$LOG_DIR/kiosk.log"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" | tee -a "$LOG_FILE"
}

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
else
  log "Config-Datei existiert bereits."
fi

source "$CONFIG_FILE"

log "Config geladen: WEBSITE_URL=$WEBSITE_URL FALLBACK_URL=$FALLBACK_URL"

# ==========================
# System & Pakete
# ==========================

sudo apt update && sudo apt upgrade -y
log "System aktualisiert."

sudo apt install --no-install-recommends -y xserver-xorg x11-xserver-utils xinit openbox
sudo apt install -y chromium unclutter xdotool curl
log "Pakete installiert."

sudo raspi-config nonint do_boot_behaviour B2
log "Autologin aktiviert."

# ==========================
# GPU / HDMI / Performance
# ==========================

sudo sed -i '/hdmi_force_hotplug/d' /boot/config.txt
sudo sed -i '/hdmi_group/d' /boot/config.txt
sudo sed -i '/hdmi_mode/d' /boot/config.txt
sudo tee -a /boot/config.txt >/dev/null <<EOF
hdmi_force_hotplug=1
hdmi_group=1
hdmi_mode=16
EOF
log "HDMI konfiguriert."

sudo sed -i '/gpu_mem/d' /boot/config.txt
echo "gpu_mem=256" | sudo tee -a /boot/config.txt >/dev/null
log "GPU-Speicher gesetzt."

sudo sed -i '/dtoverlay=vc4-kms-v3d/d' /boot/config.txt
echo "dtoverlay=vc4-kms-v3d" | sudo tee -a /boot/config.txt >/dev/null
log "KMS aktiviert."

sudo rm -f /etc/X11/xorg.conf.d/99-pi.conf
log "fbdev entfernt."

sudo mkdir -p /etc/xdg/openbox
sudo tee /etc/xdg/openbox/autostart >/dev/null <<EOF
@xset s off
@xset -dpms
@xset s noblank
EOF
log "Energiesparfunktionen deaktiviert."

sudo bash -c 'cat > /etc/network/if-up.d/wlan-reconnect <<EOF
#!/bin/bash
iwconfig wlan0 power off || true
EOF'
sudo chmod +x /etc/network/if-up.d/wlan-reconnect
log "WLAN Power Saving deaktiviert."

# ==========================
# GPU-optimierter Chromium-Start
# ==========================

cat > "$USER_HOME/start-chromium.sh" <<EOF
#!/bin/bash
source "$CONFIG_FILE"

LOG_FILE="$LOG_FILE"
log() { echo "\$(date '+%Y-%m-%d %H:%M:%S')  \$1" >> "\$LOG_FILE"; }

export DISPLAY=:0

log "Starte Chromium mit URL: \$WEBSITE_URL"

chromium \\
  --kiosk "\$WEBSITE_URL" \\
  --noerrdialogs \\
  --disable-infobars \\
  --disable-session-crashed-bubble \\
  --autoplay-policy=no-user-gesture-required \\
  --use-gl=egl \\
  --enable-features=VaapiVideoDecoder \\
  --ignore-gpu-blocklist \\
  --enable-zero-copy \\
  --disable-dev-shm-usage \\
  --disk-cache-size=104857600 \\
  --force-dark-mode \\
  --no-first-run \\
  --no-default-browser-check &
EOF

chmod +x "$USER_HOME/start-chromium.sh"
log "start-chromium.sh erstellt."

# ==========================
# X-Start
# ==========================

cat > "$USER_HOME/.xinitrc" <<EOF
#!/bin/bash
export DISPLAY=:0
openbox-session &
unclutter &
$USER_HOME/start-chromium.sh
EOF

chmod +x "$USER_HOME/.xinitrc"
log ".xinitrc erstellt."

# ==========================
# Autostart
# ==========================

if ! grep -q "KIOSK_AUTOSTART" "$USER_HOME/.bash_profile"; then
  cat >> "$USER_HOME/.bash_profile" <<'EOF'

# KIOSK_AUTOSTART
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  sleep 30
  while ! ping -c 1 8.8.8.8 >/dev/null 2>&1; do sleep 3; done
  startx
fi
EOF
fi

log "Autostart eingerichtet."

# ==========================
# Browser-Watchdog
# ==========================

cat > "$USER_HOME/kiosk-watchdog.sh" <<EOF
#!/bin/bash
source "$CONFIG_FILE"

LOG_FILE="$LOG_FILE"
log() { echo "\$(date '+%Y-%m-%d %H:%M:%S')  \$1" >> "\$LOG_FILE"; }

export DISPLAY=:0

log "Browser-Watchdog gestartet."

while true; do
    if ! pgrep -x "chromium" >/dev/null; then
        log "Chromium abgestürzt – Neustart."
        $USER_HOME/start-chromium.sh
    fi
    sleep 5
done
EOF

chmod +x "$USER_HOME/kiosk-watchdog.sh"

mkdir -p "$USER_HOME/.config/autostart"
cat > "$USER_HOME/.config/autostart/watchdog.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Kiosk Watchdog
Exec=$USER_HOME/kiosk-watchdog.sh
EOF

log "Browser-Watchdog aktiviert."

# ==========================
# Netzwerk-Watchdog
# ==========================

cat > "$USER_HOME/network-watchdog.sh" <<EOF
#!/bin/bash
source "$CONFIG_FILE"

LOG_FILE="$LOG_FILE"
log() { echo "\$(date '+%Y-%m-%d %H:%M:%S')  \$1" >> "\$LOG_FILE"; }

export DISPLAY=:0

LAST_STATE="unknown"

log "Netzwerk-Watchdog gestartet."

while true; do
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        if [ "\$LAST_STATE" != "online" ]; then
            log "ONLINE – lade Hauptseite."
            xdotool search --onlyvisible --class chromium windowactivate --sync key --clearmodifiers "ctrl+l" type "\$WEBSITE_URL" key Return
            LAST_STATE="online"
        fi
    else
        if [ "\$LAST_STATE" != "offline" ]; then
            log "OFFLINE – lade Fallback."
            xdotool search --onlyvisible --class chromium windowactivate --sync key --clearmodifiers "ctrl+l" type "\$FALLBACK_URL" key Return
            LAST_STATE="offline"
        fi
    fi
    sleep 10
done
EOF

chmod +x "$USER_HOME/network-watchdog.sh"

cat > "$USER_HOME/.config/autostart/network-watchdog.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Network Watchdog
Exec=$USER_HOME/network-watchdog.sh
EOF

log "Netzwerk-Watchdog aktiviert."

# ==========================
# Offline-Fallback
# ==========================

mkdir -p "$USER_HOME/offline"
cat > "$USER_HOME/offline/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Offline</title>
<style>
body { background:black; color:white; font-size:40px; text-align:center; padding-top:20%; }
</style>
</head>
<body>Offline – Verbindung wird wiederhergestellt…</body>
</html>
EOF

log "Offline-Fallback erstellt."

# ==========================
# Logrotate
# ==========================

sudo bash -c 'cat > /etc/logrotate.d/kiosk <<EOF
/home/pi/kiosk-logs/kiosk.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 644 pi pi
    dateext
    dateformat -%Y%m%d
    sharedscripts
    postrotate
        true
    endscript
}
EOF'

log "logrotate eingerichtet."

# ==========================
# Reboot-Cronjob
# ==========================

sudo bash -c '(crontab -l 2>/dev/null; echo "0 4 * * * /sbin/reboot") | crontab -'
log "Täglicher Reboot eingerichtet."

log "Setup abgeschlossen. Neustart empfohlen."

echo "=== Installation abgeschlossen ==="
