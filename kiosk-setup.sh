#!/bin/bash

# ============================================
# Raspberry Pi OS Lite Kiosk Installer (Pi 5)
# ============================================

URL="https://DEINE-WEBSITE.de"

echo "System aktualisieren..."
sudo apt update && sudo apt upgrade -y

echo "Benötigte Pakete installieren..."
sudo apt install --no-install-recommends xserver-xorg x11-xserver-utils xinit openbox -y
sudo apt install chromium curl -y
sudo apt install v4l2loopback-utils mesa-va-drivers -y

echo "Chromium Hardwarebeschleunigung aktivieren..."
mkdir -p ~/.config/chromium
cat <<EOF > ~/.config/chromium/Default/Preferences
{
  "hardware_acceleration_mode": {
    "enabled": true
  }
}
EOF

echo "Openbox Autostart konfigurieren..."
mkdir -p ~/.config/openbox
cat <<EOF > ~/.config/openbox/autostart
xset s off
xset -dpms
xset s noblank
/usr/local/bin/kiosk-loop.sh &
EOF

echo "Xinitrc erstellen..."
cat <<EOF > ~/.xinitrc
#!/bin/bash
xset s off
xset -dpms
xset s noblank
/usr/local/bin/kiosk-loop.sh
EOF
chmod +x ~/.xinitrc

echo "Chromium Loop-Skript erstellen..."
sudo bash -c "cat <<EOF > /usr/local/bin/kiosk-loop.sh
#!/bin/bash
while true; do
    chromium --enable-features=VaapiVideoDecoder --ignore-gpu-blocklist --noerrdialogs --disable-infobars --kiosk \"$URL\"
    echo 'Chromium abgestürzt – Neustart in 3 Sekunden'
    sleep 3
done
EOF"
sudo chmod +x /usr/local/bin/kiosk-loop.sh

echo "Watchdog-Skript erstellen..."
sudo bash -c "cat <<EOF > /usr/local/bin/kiosk-watchdog.sh
#!/bin/bash
if ! curl -s --head \"$URL\" | grep '200 OK' > /dev/null; then
    echo 'Website nicht erreichbar – Chromium wird neu gestartet'
    pkill chromium
    sleep 2
    chromium --enable-features=VaapiVideoDecoder --ignore-gpu-blocklist --noerrdialogs --disable-infobars --kiosk \"$URL\" &
fi
EOF"
sudo chmod +x /usr/local/bin/kiosk-watchdog.sh

echo "Cronjobs einrichten..."
( crontab -l 2>/dev/null; echo "*/2 * * * * /usr/local/bin/kiosk-watchdog.sh" ) | crontab -
sudo bash -c "( crontab -l 2>/dev/null; echo '0 4 * * * /sbin/reboot' ) | crontab -"

echo "Autologin aktivieren..."
sudo raspi-config nonint do_boot_behaviour B2

echo "Startx beim Login aktivieren..."
cat <<EOF >> ~/.bash_profile
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
  startx
fi
EOF

echo "Installation abgeschlossen!"
echo "Bitte Raspberry Pi neu starten."
