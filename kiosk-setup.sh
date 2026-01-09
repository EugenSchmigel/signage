#!/bin/bash

echo "=== Raspberry Pi 5 Digital Signage Setup (Minimal Desktop) ==="

WEBSITE_URL="https://DEINE-WEBSITE.de"
FALLBACK_URL="file:///home/pi/offline/index.html"

echo "→ System aktualisieren..."
sudo apt update && sudo apt upgrade -y

echo "→ Minimalen X-Server installieren..."
sudo apt install --no-install-recommends -y xserver-xorg x11-xserver-utils xinit

echo "→ Openbox installieren (leichtester Window Manager)..."
sudo apt install --no-install-recommends -y openbox

echo "→ Chromium installieren..."
sudo apt install -y chromium-browser

echo "→ unclutter installieren (Mauszeiger ausblenden)..."
sudo apt install -y unclutter

echo "→ xdotool installieren (für Netzwerk-Watchdog)..."
sudo apt install -y xdotool

echo "→ Autologin auf Konsole aktivieren..."
sudo raspi-config nonint do_boot_behaviour B2

echo "→ HDMI dauerhaft aktiv halten..."
sudo sed -i '$a hdmi_force_hotplug=1' /boot/config.txt
sudo sed -i '$a hdmi_group=1' /boot/config.txt
sudo sed -i '$a hdmi_mode=16' /boot/config.txt

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

echo "→ Openbox Autostart konfigurieren..."
mkdir -p ~/.config/openbox
cat > ~/.config/openbox/autostart <<EOF
unclutter &
chromium --kiosk $WEBSITE_URL --noerrdialogs --disable-infobars --disable-session-crashed-bubble &
EOF

echo "→ Kiosk-Start über ~/.bash_profile einrichten..."
cat >> ~/.bash_profile <<EOF

# Auto-start X + Openbox + Chromium mit Delay + Internet-Check
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then

  echo "Warte 20 Sekunden, damit Netzwerk + große Videos laden können..."
  sleep 20

  echo "Prüfe Internetverbindung..."
  while ! ping -c 1 8.8.8.8 >/dev/null 2>&1; do
      echo "Noch kein Internet – warte..."
      sleep 2
  done

  echo "Internet verfügbar – starte X + Openbox."
  startx
fi
EOF

echo "→ Browser-Watchdog erstellen..."
cat > ~/kiosk-watchdog.sh <<EOF
#!/bin/bash
while true; do
    if ! pgrep -x "chromium" > /dev/null; then
        chromium --kiosk $WEBSITE_URL --noerrdialogs --disable-infobars &
    fi
    sleep 10
done
EOF

chmod +x ~/kiosk-watchdog.sh

echo "→ Browser-Watchdog in Autostart eintragen..."
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/watchdog.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Kiosk Watchdog
Exec=/home/pi/kiosk-watchdog.sh
EOF

echo "→ Netzwerk-Watchdog erstellen..."
cat > ~/network-watchdog.sh <<EOF
#!/bin/bash

WEBSITE_URL="$WEBSITE_URL"
FALLBACK_URL="$FALLBACK_URL"

while true; do
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        xdotool search --onlyvisible --class chromium windowactivate --sync key --clearmodifiers "ctrl+l" type "\$WEBSITE_URL" key Return
    else
        xdotool search --onlyvisible --class chromium windowactivate --sync key --clearmodifiers "ctrl+l" type "\$FALLBACK_URL" key Return
    fi
    sleep 10
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

echo "→ Offline-Fallback vorbereiten..."
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

