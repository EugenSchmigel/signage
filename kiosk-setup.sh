#!/bin/bash

echo "=== Raspberry Pi 5 Digital Signage Setup – Voll optimiert ==="

# ==========================
# Basis-Konfiguration
# ==========================

USER_HOME="/home/pi"
WEBSITE_URL="https://test.test.tech"
FALLBACK_URL="file://$USER_HOME/offline/index.html"

echo "→ System aktualisieren..."
sudo apt update && sudo apt upgrade -y

echo "→ Minimalen X-Server + Openbox installieren..."
sudo apt install --no-install-recommends -y xserver-xorg x11-xserver-utils xinit openbox

echo "→ Chromium + Tools installieren..."
sudo apt install -y chromium unclutter xdotool curl

echo "→ Autologin auf Konsole aktivieren..."
sudo raspi-config nonint do_boot_behaviour B2

# ==========================
# GPU / HDMI / Performance
# ==========================

echo "→ HDMI aktiv halten + 1080p erzwingen..."
sudo sed -i '/hdmi_force_hotplug/d' /boot/config.txt
sudo sed -i '/hdmi_group/d' /boot/config.txt
sudo sed -i '/hdmi_mode/d' /boot/config.txt
sudo tee -a /boot/config.txt >/dev/null <<EOF
hdmi_force_hotplug=1
hdmi_group=1
hdmi_mode=16
EOF

echo "→ GPU-Speicher erhöhen..."
sudo sed -i '/gpu_mem/d' /boot/config.txt
echo "gpu_mem=256" | sudo tee -a /boot/config.txt >/dev/null

echo "→ KMS aktivieren (Hardware-Beschleunigung)..."
sudo sed -i '/dtoverlay=vc4-kms-v3d/d' /boot/config.txt
echo "dtoverlay=vc4-kms-v3d" | sudo tee -a /boot/config.txt >/dev/null

echo "→ fbdev-Konfiguration entfernen (falls vorhanden)..."
sudo rm -f /etc/X11/xorg.conf.d/99-pi.conf

echo "→ Energiesparfunktionen für X deaktivieren..."
sudo mkdir -p /etc/xdg/openbox
sudo sed -i '/xset s off/d' /etc/xdg/openbox/autostart 2>/dev/null || true
sudo sed -i '/xset -dpms/d' /etc/xdg/openbox/autostart 2>/dev/null || true
sudo sed -i '/xset s noblank/d' /etc/xdg/openbox/autostart 2>/dev/null || true
sudo tee -a /etc/xdg/openbox/autostart >/dev/null <<EOF
@xset s off
@xset -dpms
@xset s noblank
EOF

echo "→ WLAN Power Saving deaktivieren..."
sudo bash -c 'cat > /etc/network/if-up.d/wlan-reconnect <<EOF
#!/bin/bash
iwconfig wlan0 power off || true
EOF'
sudo chmod +x /etc/network/if-up.d/wlan-reconnect

# ==========================
# Chromium Start (GPU-optimiert)
# ==========================

echo "→ GPU-optimierte Chromium-Startdatei erstellen..."
cat > "$USER_HOME/start-chromium.sh" <<EOF
#!/bin/bash
export DISPLAY=:0

chromium \\
  --kiosk "$WEBSITE_URL" \\
  --noerrdialogs \\
  --disable-infobars \\
  --disable-session-crashed-bubble \\
  --autoplay-policy=no-user-gesture-required \\
  --use-gl=egl \\
  --enable-features=VaapiVideoDecoder \\
  --ignore-gpu-blocklist \\
  --disable-features=UseChromeOSDirectVideoDecoder \\
  --disable-gpu-driver-bug-workarounds \\
  --disable-low-res-tiling \\
  --disable-accelerated-video-decode=false \\
  --enable-zero-copy \\
  --disk-cache-size=104857600 \\
  --force-dark-mode \\
  --no-first-run \\
  --no-default-browser-check \\
  --disable-dev-shm-usage \\
  --password-store=basic \\
  --overscroll-history-navigation=0 \\
  --disable-pinch \\
  --disable-features=TranslateUI &
EOF
chmod +x "$USER_HOME/start-chromium.sh"

# ==========================
# X-Start (.xinitrc)
# ==========================

echo "→ .xinitrc erstellen..."
cat > "$USER_HOME/.xinitrc" <<EOF
#!/bin/bash
export DISPLAY=:0

openbox-session &
unclutter &

$USER_HOME/start-chromium.sh
EOF
chmod +x "$USER_HOME/.xinitrc"

# ==========================
# Autostart über .bash_profile
# ==========================

echo "→ Autostart über ~/.bash_profile einrichten..."
if ! grep -q "KIOSK_AUTOSTART" "$USER_HOME/.bash_profile" 2>/dev/null; then
  cat >> "$USER_HOME/.bash_profile" <<'EOF'

# KIOSK_AUTOSTART
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  echo "Warte 30 Sekunden für Netzwerk + GPU-Init..."
  sleep 30

  echo "Prüfe Internetverbindung..."
  while ! ping -c 1 8.8.8.8 >/dev/null 2>&1; do
      echo "Noch kein Internet – warte..."
      sleep 3
  done

  echo "Internet verfügbar – starte X..."
  startx
fi
EOF
fi

# ==========================
# Neuer, „sanfter“ Browser-Watchdog
# ==========================

echo "→ Sanften Browser-Watchdog erstellen..."
cat > "$USER_HOME/kiosk-watchdog.sh" <<EOF
#!/bin/bash
export DISPLAY=:0

while true; do
    if ! pgrep -x "chromium" >/dev/null; then
        echo "[Watchdog] Chromium nicht gefunden – starte neu..."
        $USER_HOME/start-chromium.sh
    fi
    sleep 10
done
EOF
chmod +x "$USER_HOME/kiosk-watchdog.sh"

echo "→ Watchdog in Autostart eintragen..."
mkdir -p "$USER_HOME/.config/autostart"
cat > "$USER_HOME/.config/autostart/watchdog.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Kiosk Watchdog
Exec=$USER_HOME/kiosk-watchdog.sh
EOF

# ==========================
# Neuer Netzwerk-Watchdog (nicht störend)
# ==========================

echo "→ Netzwerk-Watchdog erstellen (minimal invasiv)..."
cat > "$USER_HOME/network-watchdog.sh" <<EOF
#!/bin/bash
export DISPLAY=:0
WEBSITE_URL="$WEBSITE_URL"
FALLBACK_URL="$FALLBACK_URL"

LAST_STATE="unknown"

while true; do
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        # Online
        if [ "\$LAST_STATE" != "online" ]; then
            echo "[NetWatch] Wechsel zu ONLINE – lade Hauptseite..."
            xdotool search --onlyvisible --class chromium windowactivate --sync key --clearmodifiers "ctrl+l" type "\$WEBSITE_URL" key Return
            LAST_STATE="online"
        fi
    else
        # Offline
        if [ "\$LAST_STATE" != "offline" ]; then
            echo "[NetWatch] Wechsel zu OFFLINE – lade Fallback..."
            xdotool search --onlyvisible --class chromium windowactivate --sync key --clearmodifiers "ctrl+l" type "\$FALLBACK_URL" key Return
            LAST_STATE="offline"
        fi
    fi
    sleep 10
done
EOF
chmod +x "$USER_HOME/network-watchdog.sh"

echo "→ Netzwerk-Watchdog in Autostart eintragen..."
cat > "$USER_HOME/.config/autostart/network-watchdog.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Network Watchdog
Exec=$USER_HOME/network-watchdog.sh
EOF

# ==========================
# Offline-Fallback
# ==========================

echo "→ Offline-Fallback erstellen..."
mkdir -p "$USER_HOME/offline"
cat > "$USER_HOME/offline/index.html" <<EOF
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8" />
  <title>Offline – Verbindung wird wiederhergestellt…</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <style>
    body {
      margin: 0;
      background: #000;
      color: #fff;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      text-align: center;
    }
    .msg {
      font-size: 2.4rem;
      max-width: 80vw;
    }
  </style>
</head>
<body>
  <div class="msg">
    Offline – Verbindung wird wiederhergestellt…
  </div>
</body>
</html>
EOF

# ==========================
# Täglicher Reboot
# ==========================

echo "→ Täglichen Reboot um 04:00 Uhr einrichten..."
sudo bash -c '(crontab -l 2>/dev/null; echo "0 4 * * * /sbin/reboot") | crontab -'

echo "=== Installation abgeschlossen ==="
echo "Bitte Raspberry Pi neu starten."
