#!/bin/bash
set -e

USER_NAME="$(whoami)"
USER_HOME="/home/$USER_NAME"
CONFIG_FILE="$USER_HOME/signage.conf"
AUTOSTART_DIR="$USER_HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/chromium-kiosk.desktop"
SCREEN_FILE="$AUTOSTART_DIR/screen-settings.desktop"
CHROMIUM_CUSTOM="/etc/chromium-browser/customizations/01-kiosk"
RESTART_SCRIPT="$USER_HOME/restart-chromium.sh"
CHROMIUM_MONITOR="/usr/local/bin/chromium-monitor.sh"
CHROMIUM_MONITOR_SERVICE="/etc/systemd/system/chromium-monitor.service"

echo "----------------------------------------"
echo " Raspberry Pi Signage Installer"
echo "----------------------------------------"
echo

ask() {
    read -p "$1 (j/n): " answer
    [[ "$answer" == "j" ]]
}

# ---------------------------------------------------------
# URL
# ---------------------------------------------------------
echo
echo "---------------------------------------------------------"
echo " URL für Kiosk-Modus"
echo "---------------------------------------------------------"

read -p "Welche URL soll im Kiosk-Modus angezeigt werden? " SIGNAGE_URL
echo "URL=$SIGNAGE_URL" > "$CONFIG_FILE"
echo "Config gespeichert unter: $CONFIG_FILE"


# ---------------------------------------------------------
# Chromium Kiosk Autostart
# ---------------------------------------------------------
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

    echo "Kiosk-Autostart eingerichtet: $AUTOSTART_FILE"
fi


# ---------------------------------------------------------
# Autologin
# ---------------------------------------------------------
echo
echo "---------------------------------------------------------"
echo " Autologin"
echo "---------------------------------------------------------"

if ask "Autologin aktivieren"; then
    sudo raspi-config nonint do_boot_behaviour B4
    echo "Autologin aktiviert."
fi


# ---------------------------------------------------------
# Bildschirm-Timeout
# ---------------------------------------------------------
echo
echo "---------------------------------------------------------"
echo " Bildschirm-Timeout"
echo "---------------------------------------------------------"

if ask "Bildschirm-Timeout deaktivieren"; then
    mkdir -p "$AUTOSTART_DIR"
    cat <<EOF > "$SCREEN_FILE"
[Desktop Entry]
Type=Application
Name=Screen Settings
Exec=xset s off && xset -dpms && xset s noblank
EOF
    echo "Bildschirm bleibt dauerhaft aktiv: $SCREEN_FILE"
fi


# ---------------------------------------------------------
# Mauszeiger
# ---------------------------------------------------------
echo
echo "---------------------------------------------------------"
echo " Mauszeiger"
echo "---------------------------------------------------------"

if ask "Mauszeiger ausblenden (unclutter installieren)"; then
    sudo apt update
    sudo apt install -y unclutter
    echo "Mauszeiger wird ausgeblendet."
fi


# ---------------------------------------------------------
# Watchdog
# ---------------------------------------------------------
echo
echo "---------------------------------------------------------"
echo " Watchdog"
echo "---------------------------------------------------------"

if ask "Watchdog aktivieren und konfigurieren"; then
    sudo apt update
    sudo apt install -y watchdog

    sudo systemctl enable watchdog
    sudo systemctl start watchdog

    # Basiskonfiguration für stabilen Signage-Betrieb
    sudo sed -i 's|^#*watchdog-device.*|watchdog-device = /dev/watchdog|' /etc/watchdog.conf || true
    sudo sed -i 's|^#*interval.*|interval = 10|' /etc/watchdog.conf || echo "interval = 10" | sudo tee -a /etc/watchdog.conf >/dev/null
    sudo sed -i 's|^#*watchdog-timeout.*|watchdog-timeout = 15|' /etc/watchdog.conf || echo "watchdog-timeout = 15" | sudo tee -a /etc/watchdog.conf >/dev/null

    # Netzwerk-Checks hinzufügen (nur wenn noch nicht vorhanden)
    if ! grep -q "^ping = 1.1.1.1" /etc/watchdog.conf; then
        echo "ping = 1.1.1.1" | sudo tee -a /etc/watchdog.conf >/dev/null
    fi
    if ! grep -q "^ping = 8.8.8.8" /etc/watchdog.conf; then
        echo "ping = 8.8.8.8" | sudo tee -a /etc/watchdog.conf >/dev/null
    fi

    # Dateisystem-Check
    if ! grep -q "^file = /var/log/syslog" /etc/watchdog.conf; then
        echo "file = /var/log/syslog" | sudo tee -a /etc/watchdog.conf >/dev/null
        echo "change = 1407" | sudo tee -a /etc/watchdog.conf >/dev/null
    fi

    # CPU-Load-Überwachung explizit deaktivieren (falls kommentiert/aktiv)
    sudo sed -i 's/^max-load-1/#max-load-1/' /etc/watchdog.conf || true

    sudo systemctl restart watchdog
    echo "Watchdog installiert und konfiguriert."
fi


# ---------------------------------------------------------
# Chromium Restart Script via Cron
# ---------------------------------------------------------
echo
echo "---------------------------------------------------------"
echo " Chromium-Neustart statt Reboot"
echo "---------------------------------------------------------"

if ask "Täglichen Chromium-Neustart um 4 Uhr einrichten"; then

cat <<EOF > "$RESTART_SCRIPT"
#!/bin/bash

CONFIG_FILE="/home/pi/signage.conf"
URL=$(grep '^URL=' "$CONFIG_FILE" | cut -d'=' -f2)

export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000

echo "[INFO] Beende Chromium..."

# Alle Chromium-Prozesse sicher beenden
pkill -9 chromium 2>/dev/null
pkill -9 chromium-browser 2>/dev/null
pkill -9 chrome 2>/dev/null
sleep 2

# Chromium-Sperrdateien entfernen (verhindert 'Chromium läuft bereits')
rm -f /home/pi/.config/chromium/Singleton*
rm -f /home/pi/.config/chromium/Default/Preferences

echo "[INFO] Starte Chromium neu..."

chromium-browser --kiosk --no-first-run --no-default-browser-check --disable-infobars --disable-session-crashed-bubble --disable-features=TranslateUI --autoplay-policy=no-user-gesture-required --incognito --new-window "$URL" &
EOF

    chmod +x "$RESTART_SCRIPT"

    (crontab -l 2>/dev/null; echo "0 4 * * * $RESTART_SCRIPT") | crontab -

    echo "Chromium-Neustart-Cronjob eingerichtet: täglich 4:00 Uhr."
fi


# ---------------------------------------------------------
# Chromium Monitor (systemd)
# ---------------------------------------------------------
echo
echo "---------------------------------------------------------"
echo " Chromium-Monitor (überwacht und startet neu bei Hängern)"
echo "---------------------------------------------------------"

if ask "Chromium-Monitor installieren (empfohlen)"; then

sudo tee "$CHROMIUM_MONITOR" >/dev/null <<EOF
#!/bin/bash

CONFIG_FILE="$CONFIG_FILE"
URL=\$(grep '^URL=' "\$CONFIG_FILE" | cut -d'=' -f2)

export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/$(id -u "$USER_NAME")

# Prüfen, ob Chromium läuft
if ! pgrep chromium-browser > /dev/null; then
    echo "[Chromium-Monitor] Chromium läuft nicht – starte neu"
    chromium-browser --kiosk --noerrdialogs --disable-infobars \\
        --disable-session-crashed-bubble --autoplay-policy=no-user-gesture-required \\
        --incognito "\$URL" &
    exit 0
fi

# CPU-Last prüfen (sehr niedrige Last kann auf Hänger hindeuten)
CPU=\$(ps -C chromium-browser -o %cpu= | awk '{sum+=\$1} END {print sum+0}')

if command -v bc >/dev/null 2>&1; then
    if (( \$(echo "\$CPU < 1.0" | bc -l) )); then
        echo "[Chromium-Monitor] Chromium reagiert nicht (CPU=\$CPU) – Neustart"
        pkill chromium-browser || true
        sleep 5
        chromium-browser --kiosk --noerrdialogs --disable-infobars \\
            --disable-session-crashed-bubble --autoplay-policy=no-user-gesture-required \\
            --incognito "\$URL" &
    fi
fi
EOF

    sudo chmod +x "$CHROMIUM_MONITOR"

    sudo tee "$CHROMIUM_MONITOR_SERVICE" >/dev/null <<EOF
[Unit]
Description=Chromium Monitor Service
After=graphical.target

[Service]
Type=simple
User=$USER_NAME
ExecStart=$CHROMIUM_MONITOR
Restart=always
RestartSec=30

[Install]
WantedBy=graphical.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable chromium-monitor.service
    sudo systemctl start chromium-monitor.service

    echo "Chromium-Monitor installiert und aktiviert."
fi


# ---------------------------------------------------------
# Logs minimieren
# ---------------------------------------------------------
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


# ---------------------------------------------------------
# Chromium Cache
# ---------------------------------------------------------
echo
echo "---------------------------------------------------------"
echo " Chromium-Cache"
echo "---------------------------------------------------------"

if ask "Chromium-Cache in RAM verschieben"; then
    sudo mkdir -p /etc/chromium-browser/customizations
    echo 'CHROMIUM_FLAGS="--disk-cache-dir=/tmp/chromium-cache"' | sudo tee "$CHROMIUM_CUSTOM" >/dev/null
    echo "Chromium-Cache wird im RAM gespeichert."
fi


# ---------------------------------------------------------
# tmpfs
# ---------------------------------------------------------
echo
echo "---------------------------------------------------------"
echo " tmpfs"
echo "---------------------------------------------------------"

if ask "/tmp als RAM-Disk einrichten"; then
    if ! grep -q "^tmpfs /tmp tmpfs" /etc/fstab; then
        echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,size=100m 0 0" | sudo tee -a /etc/fstab >/dev/null
        echo "/tmp wird als RAM-Disk genutzt."
    else
        echo "/tmp ist bereits als tmpfs eingetragen."
    fi
fi


# ---------------------------------------------------------
# Updates deaktivieren
# ---------------------------------------------------------
echo
echo "---------------------------------------------------------"
echo " Updates deaktivieren"
echo "---------------------------------------------------------"

if ask "Automatische Updates deaktivieren (empfohlen für Signage)"; then
    sudo systemctl disable --now apt-daily.service || true
    sudo systemctl disable --now apt-daily-upgrade.service || true
    sudo systemctl disable --now unattended-upgrades.service || true
    sudo systemctl mask apt-daily.service || true
    sudo systemctl mask apt-daily-upgrade.service || true

    echo "Automatische Updates deaktiviert."
fi


echo
echo "----------------------------------------"
echo " Installation abgeschlossen!"
echo " Neustart des Raspberry Pi ist empfohlen."
echo "----------------------------------------"
