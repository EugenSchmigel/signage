#!/bin/bash

echo "=== Raspberry Pi Digital Signage – Kiosk Setup (Autologin + startx) ==="

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
sudo apt install -y chromium unclutter xdotool curl jq
log "Pakete installiert."

# ==========================
# HDMI / GPU Basis
# ==========================

sudo sed -i '/dtoverlay=/d;/gpu_mem=/d;/hdmi_force_hotplug=/d/' /boot/config.txt
sudo tee -a /boot/config.txt >/dev/null <<EOF
dtoverlay=vc4-fkms-v3d
gpu_mem=256
hdmi_force_hotplug=1
EOF

# ==========================
# WLAN Stromsparmodus aus
# ==========================

sudo tee /etc/network/if-up.d/wlan-stabilize >/dev/null <<EOF
#!/bin/bash
iwconfig wlan0 power off || true
EOF
sudo chmod +x /etc/network/if-up.d/wlan-stabilize

# ==========================
# Openbox Autostart (Bildschirm an, Maus weg)
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

cat > "$USER_HOME/start-chromium.sh" <<'EOF'
#!/bin/bash
source "$HOME/kiosk.conf"
export DISPLAY=:0

chromium --kiosk "$WEBSITE_URL" \
  --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required \
  --disable-dev-shm-usage --no-first-run --no-default-browser-check \
  --force-dark-mode
EOF

chmod +x "$USER_HOME/start-chromium.sh"
chown "$USER:$USER" "$USER_HOME/start-chromium.sh"

# ==========================
# .xinitrc – wird von startx geladen
# ==========================

cat > "$USER_HOME/.xinitrc" <<EOF
#!/bin/bash
openbox-session &
$USER_HOME/start-chromium.sh
EOF

chmod +x "$USER_HOME/.xinitrc"
chown "$USER:$USER" "$USER_HOME/.xinitrc"

# ==========================
# Autologin auf TTY1
# ==========================

sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF

sudo systemctl daemon-reexec
sudo systemctl restart getty@tty1.service

# ==========================
# Automatischer Start von X nach Login
# ==========================

if ! grep -q 'startx' "$USER_HOME/.bash_profile" 2>/dev/null; then
  cat >> "$USER_HOME/.bash_profile" <<'EOF'
# Auto-start X on first TTY
if [[ -z "$DISPLAY" && "$XDG_VTNR" -eq 1 ]]; then
  startx
fi
EOF
fi

chown "$USER:$USER" "$USER_HOME/.bash_profile"

# ==========================
# Offline-Fallback-Seite
# ==========================

mkdir -p "$USER_HOME/offline"
cat > "$USER_HOME/offline/index.html" <<EOF
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Offline</title>
<style>body{background:black;color:white;font-size:40px;text-align:center;padding-top:20%;}</style>
</head><body>Offline – Verbindung wird wiederhergestellt…</body></html>
EOF
chown -R "$USER:$USER" "$USER_HOME/offline"

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

log "Setup abgeschlossen. Bitte neu starten (sudo reboot)."
