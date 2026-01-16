#!/bin/bash

echo "=== Raspberry Pi 5 Digital Signage Setup – Optimiert für Performance ==="

WEBSITE_URL="https://test.test.tech"
FALLBACK_URL="file:///home/pi/offline/index.html"

echo "→ System aktualisieren..."
sudo apt update && sudo apt upgrade -y

echo "→ Minimalen X-Server installieren..."
sudo apt install --no-install-recommends -y xserver-xorg x11-xserver-utils xinit

echo "→ Openbox installieren..."
sudo apt install --no-install-recommends -y openbox

echo "→ Chromium installieren..."
sudo apt install -y chromium

echo "→ unclutter installieren..."
sudo apt install -y unclutter

echo "→ xdotool installieren..."
sudo apt install -y xdotool

echo "→ Autologin auf Konsole aktivieren..."
sudo raspi-config nonint do_boot_behaviour B2

echo "→ HDMI aktiv halten + 1080p erzwingen..."
sudo sed -i '$a hdmi_force_hotplug=1' /boot/config.txt
sudo sed -i '$a hdmi_group=1' /boot/config.txt
sudo sed -i '$a hdmi_mode=16' /boot/config.txt

echo "→ GPU-Speicher erhöhen..."
sudo sed -i '$a gpu_mem=256' /boot/config.txt

echo "→ KMS aktivieren (Hardware-Beschleunigung)..."
sudo sed -i '/dtoverlay=vc4-kms-v3d/d' /boot/config.txt
echo "dtoverlay=vc4-kms-v3d" | sudo tee -a /boot/config.txt

echo "→ fbdev deaktivieren..."
sudo rm -f /etc/X11/xorg.conf.d/99-pi.conf

echo "→ Energiesparfunktionen deaktivieren..."
sudo sed -i '$a @xset s off' /etc/xdg/openbox/autostart
sudo sed -i '$a @xset -dpms' /etc/xdg/openbox/autostart
sudo sed -i '$a @xset s noblank' /etc/xdg/openbox/autostart

echo "→ WLAN Power Saving deaktivieren..."
sudo bash -c 'cat > /etc/network/if-up.d/wlan-reconnect <<EOF
#!/bin/bash
iwconfig wlan0 power off
EOF'
sudo chmod +x /etc/network/if-up.d/wlan-reconnect

echo "→ .xinitrc erstellen (Chromium mit Hardware-Decoding)..."
cat > ~/.xinitrc <<EOF
#!/bin/bash
export DISPLAY=:0

openbox-session &
unclutter &

chromium \
  --kiosk "$WEBSITE_URL" \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required \
  --use-gl=egl \
  --enable-features=VaapiVideoDecoder \
  --ignore-gpu-blocklist \
  --disable-features=UseChromeOSDirectVideoDecoder \
  --disable-gpu-driver-bug-workarounds \
  --disable-low-res-tiling \
  --disable-accelerated-video-decode=false \
  --enable-zero-copy \
  --force-dark-mode \
  --disk-cache-size=104857600 &
EOF
chmod +x ~/.xinitrc

echo "→ Autostart über ~/.bash_profile einrichten..."
cat >> ~/.bash_profile <<EOF

# Auto-start X + Openbox + Chromium
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then

  echo "Warte 30 Sekunden für Netzwerk + GPU-Init..."
  sleep 30

  echo "Prüfe Internetverbindung..."
  while ! ping -c 1 8.8.8.8 >/dev/null 2>&1; do
      echo "Noch kein Internet – warte..."
      sleep 2
  done

  echo "Internet verfügbar – starte X."
  startx
fi
EOF

echo "→ Browser-Watchdog erstellen (nur neu starten, wenn Chromium wirklich abgestürzt ist)..."
cat > ~/kiosk-watchdog.sh <<EOF
#!/bin/bash
export DISPLAY=:0
while true; do
    if ! pgrep -x "chromium" > /dev/null; then
        chromium \
          --kiosk "$WEBSITE_URL" \
          --noerrdialogs \
          --disable-infobars \
          --disable-session-crashed-bubble \
          --autoplay-policy=no-user-gesture-required \
          --use-gl=egl \
          --enable-features=VaapiVideoDecoder \
          --ignore-gpu-blocklist \
          --enable-zero-copy &
    fi
    sleep 10
done
EOF
chmod +x ~/kiosk-watchdog.sh

echo "→ Watchdog in Autostart eintragen..."
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/watchdog.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Kiosk Watchdog
Exec=/home/pi/kiosk-watchdog.sh
EOF

echo "→ Netzwerk-Watchdog optimiert erstellen..."
cat > ~/network-watchdog.sh <<EOF
#!/bin/bash
export DISPLAY=:0
WEBSITE_URL="$WEBSITE_URL"
FALLBACK_URL="$FALLBACK_URL"

while true; do
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        # Nur neu laden, wenn Seite nicht erreichbar
        if ! curl -s --head --fail "\$WEBSITE_URL" >/dev/null; then
            xdotool search --onlyvisible --class chromium windowactivate --sync key --clearmodifiers "ctrl+r"
        fi
    else
        xdotool search --onlyvisible --class chromium windowactivate --sync key --clearmodifiers "ctrl+l" type "\$FALLBACK_URL" key Return
    fi
    sleep 15
done
EOF
chmod +x ~/network-watchdog.sh

echo "→ Netzwerk-Watchdog in Autostart eintragen..."
cat > ~/.config/autostart/network-watchdog.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Network Watchdog
Exec=/home/pi/network-watchdog.sh
EOF

echo "→ Offline-Fallback erstellen..."
mkdir -p ~/offline
cat > ~/offline/index.html <<EOF
<html>
  <body style="background:black;color:white;font-size:40px;text-align:center;padding-top:20%;">
    <p>Offline – Verbindung wird wiederhergestellt…</p>
  </body>
</html>
EOF

echo "→ Täglichen Reboot um 04:00 Uhr einrichten..."
sudo bash -c '(crontab -l 2>/dev/null; echo "0 4 * * * /sbin/reboot") | crontab -'

echo "=== Installation abgeschlossen ==="
echo "Bitte Raspberry Pi neu starten."
