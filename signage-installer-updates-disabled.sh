#!/bin/bash

CONFIG_FILE="/home/$USER/signage.conf"
AUTOSTART_DIR="/home/$USER/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/chromium-kiosk.desktop"
SCREEN_FILE="$AUTOSTART_DIR/screen-settings.desktop"
CHROMIUM_CUSTOM="/etc/chromium-browser/customizations/01-kiosk"
RESTART_SCRIPT="/home/$USER/restart-chromium.sh"

echo "----------------------------------------"
echo " Raspberry Pi Signage Installer (interaktiv)"
echo "----------------------------------------"
echo

ask() {
read -p "$1 (j/n): " answer
[[ "$answer" == "j" ]]
}

echo
echo "---------------------------------------------------------"
echo " URL abfragen"
echo "---------------------------------------------------------"

read -p "Welche URL soll im Kiosk-Modus angezeigt werden? " SIGNAGE_URL
echo "URL=$SIGNAGE_URL" > "$CONFIG_FILE"
echo "Config gespeichert unter: $CONFIG_FILE"
echo

echo "---------------------------------------------------------"
echo " Chromium-Kiosk"
echo "---------------------------------------------------------"

if ask "Chromium-Kiosk-Modus einrichten"; then
mkdir -p "$AUTOSTART_DIR"
cat <<EOF > "$AUTOSTART_FILE"
[Desktop Entry]
Type=Application
Name=Chromium Kiosk
Exec=chromium-browser --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble --autoplay-policy=no-user-gesture-required --incognito $SIGNAGE_URL
EOF
echo "Kiosk-Autostart eingerichtet."
fi

echo
echo "---------------------------------------------------------"
echo " Autologin"
echo "---------------------------------------------------------"

if ask "Autologin aktivieren"; then
sudo raspi-config nonint do_boot_behaviour B4
echo "Autologin aktiviert."
fi

echo
echo "---------------------------------------------------------"
echo " Bildschirm-Timeout"
echo "---------------------------------------------------------"

if ask "Bildschirm-Timeout deaktivieren"; then
cat <<EOF > "$SCREEN_FILE"
[Desktop Entry]
Type=Application
Name=Screen Settings
Exec=xset s off && xset -dpms && xset s noblank
EOF
echo "Bildschirm bleibt dauerhaft aktiv."
fi

echo
echo "---------------------------------------------------------"
echo " Mauszeiger"
echo "---------------------------------------------------------"

if ask "Mauszeiger ausblenden (unclutter installieren)"; then
sudo apt install -y unclutter
echo "Mauszeiger wird ausgeblendet."
fi

echo
echo "---------------------------------------------------------"
echo " Watchdog"
echo "---------------------------------------------------------"

if ask "Watchdog aktivieren"; then
sudo apt install -y watchdog
sudo systemctl enable watchdog
sudo systemctl start watchdog

sudo sed -i 's/#watchdog-device/watchdog-device/' /etc/watchdog.conf
sudo sed -i 's/#max-load-1/max-load-1/' /etc/watchdog.conf
echo "ping = 8.8.8.8" | sudo tee -a /etc/watchdog.conf >/dev/null

echo "Watchdog aktiviert."

fi

echo
echo "---------------------------------------------------------"
echo " Chromium-Neustart statt Reboot"
echo "---------------------------------------------------------"

if ask "Täglichen Chromium-Neustart um 4 Uhr einrichten"; then

# Restart-Script erstellen
cat <<'EOF' > "$RESTART_SCRIPT"

#!/bin/bash

CONFIG_FILE="/home/$USER/signage.conf"
URL=$(grep '^URL=' "$CONFIG_FILE" | cut -d'=' -f2)

Chromium beenden

pkill chromium-browser
sleep 5

Chromium neu starten

export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000

chromium-browser --kiosk --noerrdialogs --disable-infobars 
--disable-session-crashed-bubble --autoplay-policy=no-user-gesture-required 
--incognito "$URL" &
EOF

chmod +x "$RESTART_SCRIPT"

# Cronjob einrichten
(crontab -l 2>/dev/null; echo "0 4 * * * /home/$USER/restart-chromium.sh") | crontab -

echo "Chromium-Neustart-Cronjob eingerichtet."

fi

echo
echo "---------------------------------------------------------"
echo " Logs minimieren"
echo "---------------------------------------------------------"

if ask "Logs minimieren (SD-Karte schonen)"; then
sudo sed -i 's/#Storage=auto/Storage=volatile/' /etc/systemd/journald.conf
sudo sed -i 's/#RuntimeMaxUse=/RuntimeMaxUse=50M/' /etc/systemd/journald.conf
sudo systemctl restart systemd-journald
echo "Logs werden im RAM gespeichert."
fi

echo
echo "---------------------------------------------------------"
echo " Chromium-Cache"
echo "---------------------------------------------------------"

if ask "Chromium-Cache in RAM verschieben"; then
sudo mkdir -p /etc/chromium-browser/customizations
echo 'CHROMIUM_FLAGS="--disk-cache-dir=/tmp/chromium-cache"' | sudo tee "$CHROMIUM_CUSTOM"
echo "Chromium-Cache wird im RAM gespeichert."
fi

echo
echo "---------------------------------------------------------"
echo " tmpfs"
echo "---------------------------------------------------------"

if ask "/tmp als RAM-Disk einrichten"; then
echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,size=100m 0 0" | sudo tee -a /etc/fstab
echo "/tmp wird als RAM-Disk genutzt."
fi

echo
echo "---------------------------------------------------------"
echo " Updates deaktivieren"
echo "---------------------------------------------------------"

if ask "Automatische Updates deaktivieren (empfohlen für Signage)"; then
sudo systemctl disable --now apt-daily.service
sudo systemctl disable --now apt-daily-upgrade.service
sudo systemctl disable --now unattended-upgrades.service
sudo systemctl mask apt-daily.service
sudo systemctl mask apt-daily-upgrade.service

echo "Automatische Updates deaktiviert."

fi

echo "----------------------------------------"
echo " Installation abgeschlossen!"
echo " Neustart empfohlen."
echo "----------------------------------------"
