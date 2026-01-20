#!/bin/bash

CONFIG_FILE="/home/$USER/signage.conf"
AUTOSTART_DIR="/home/$USER/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/chromium-kiosk.desktop"

echo "----------------------------------------"
echo " Raspberry Pi Signage Setup (interaktiv)"
echo "----------------------------------------"
echo

# ---------------------------------------------------------
# URL abfragen und in Config speichern
# ---------------------------------------------------------

read -p "Welche URL soll im Kiosk-Modus angezeigt werden? " SIGNAGE_URL

echo "URL=$SIGNAGE_URL" > "$CONFIG_FILE"
echo "Config gespeichert unter: $CONFIG_FILE"
echo

# Wayland deaktivieren (X11 aktivieren)
if ask "Wayland deaktivieren und X11 aktivieren (empfohlen für Kiosk-Modus)"; then
    sudo raspi-config nonint do_wayland W1
    echo "Wayland deaktiviert, X11 aktiviert."
fi


# ---------------------------------------------------------
# Abfragefunktion
# ---------------------------------------------------------

ask() {
    read -p "$1 (j/n): " answer
    [[ "$answer" == "j" ]]
}

# ---------------------------------------------------------
# Autostart + Kiosk-Modus
# ---------------------------------------------------------

if ask "Chromium-Kiosk-Modus einrichten"; then
    mkdir -p "$AUTOSTART_DIR"

    cat <<EOF > "$AUTOSTART_FILE"
[Desktop Entry]
Type=Application
Name=Chromium Kiosk
Exec=chromium-browser --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble --autoplay-policy=no-user-gesture-required --incognito $SIGNAGE_URL
EOF

    echo "Kiosk-Autostart eingerichtet."
    echo
fi

# ---------------------------------------------------------
# Autologin aktivieren
# ---------------------------------------------------------

if ask "Autologin aktivieren"; then
    sudo raspi-config nonint do_boot_behaviour B4
    echo "Autologin aktiviert."
    echo
fi

# ---------------------------------------------------------
# Bildschirm-Timeout deaktivieren
# ---------------------------------------------------------

if ask "Bildschirm-Timeout deaktivieren"; then
    mkdir -p "$AUTOSTART_DIR"

    cat <<EOF > "$AUTOSTART_DIR/screen-settings.desktop"
[Desktop Entry]
Type=Application
Name=Screen Settings
Exec=xset s off && xset -dpms && xset s noblank
EOF

    echo "Bildschirm bleibt dauerhaft aktiv."
    echo
fi

# ---------------------------------------------------------
# Mauszeiger ausblenden
# ---------------------------------------------------------

# Mauszeiger
if ask "Mauszeiger ausblenden (unclutter installieren)"; then
    sudo apt install -y unclutter

    mkdir -p "$AUTOSTART_DIR"
    cat <<EOF > "$AUTOSTART_DIR/unclutter.desktop"
[Desktop Entry]
Type=Application
Name=Unclutter
Exec=unclutter -idle 0 -root
EOF

    echo "Mauszeiger wird ausgeblendet (Autostart eingerichtet)."
fi


# ---------------------------------------------------------
# Watchdog aktivieren
# ---------------------------------------------------------

if ask "Watchdog aktivieren"; then
    sudo apt install -y watchdog
    sudo systemctl enable watchdog
    sudo systemctl start watchdog

    sudo sed -i 's/#watchdog-device/watchdog-device/' /etc/watchdog.conf
    sudo sed -i 's/#max-load-1/max-load-1/' /etc/watchdog.conf
    echo "ping = 8.8.8.8" | sudo tee -a /etc/watchdog.conf >/dev/null

    echo "Watchdog aktiviert."
    echo
fi

# ---------------------------------------------------------
# Cronjob für täglichen Neustart
# ---------------------------------------------------------

if ask "Täglichen Neustart um 4 Uhr einrichten"; then
    (sudo crontab -l 2>/dev/null; echo "0 4 * * * /sbin/reboot") | sudo crontab -
    echo "Cronjob eingerichtet."
    echo
fi

# ---------------------------------------------------------
# Logs minimieren
# ---------------------------------------------------------

if ask "Logs minimieren (SD-Karte schonen)"; then
    sudo sed -i 's/#Storage=auto/Storage=volatile/' /etc/systemd/journald.conf
    sudo sed -i 's/#RuntimeMaxUse=/RuntimeMaxUse=50M/' /etc/systemd/journald.conf
    sudo systemctl restart systemd-journald

    echo "Logs werden jetzt im RAM gespeichert."
    echo
fi

# ---------------------------------------------------------
# Chromium-Cache in RAM
# ---------------------------------------------------------

if ask "Chromium-Cache in RAM verschieben"; then
    sudo mkdir -p /etc/chromium-browser/customizations
    echo 'CHROMIUM_FLAGS="--disk-cache-dir=/tmp/chromium-cache"' | sudo tee /etc/chromium-browser/customizations/01-kiosk
    echo "Chromium-Cache wird im RAM gespeichert."
    echo
fi

# ---------------------------------------------------------
# /tmp als tmpfs
# ---------------------------------------------------------

if ask "/tmp als RAM-Disk einrichten"; then
    echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,size=100m 0 0" | sudo tee -a /etc/fstab
    echo "/tmp wird als RAM-Disk genutzt."
    echo
fi

echo "----------------------------------------"
echo " Setup abgeschlossen!"
echo " Neustart empfohlen."
echo "----------------------------------------"
