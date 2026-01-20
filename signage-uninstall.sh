#!/bin/bash

CONFIG_FILE="/home/$USER/signage.conf"
AUTOSTART_DIR="/home/$USER/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/chromium-kiosk.desktop"
SCREEN_FILE="$AUTOSTART_DIR/screen-settings.desktop"
CHROMIUM_CUSTOM="/etc/chromium-browser/customizations/01-kiosk"

echo "----------------------------------------"
echo " Raspberry Pi Signage Uninstaller (interaktiv)"
echo "----------------------------------------"
echo

ask() {
    read -p "$1 (j/n): " answer
    [[ "$answer" == "j" ]]
}

# ---------------------------------------------------------
# Autostart entfernen
# ---------------------------------------------------------

if ask "Chromium-Kiosk-Autostart entfernen"; then
    rm -f "$AUTOSTART_FILE"
    echo "Kiosk-Autostart entfernt."
fi

# ---------------------------------------------------------
# Bildschirm-Timeout
# ---------------------------------------------------------

if ask "Bildschirm-Timeout-Einstellungen entfernen"; then
    rm -f "$SCREEN_FILE"
    echo "Bildschirm-Timeout-Einstellungen entfernt."
fi

# ---------------------------------------------------------
# Mauszeiger
# ---------------------------------------------------------

if ask "Unclutter deinstallieren"; then
    sudo apt remove -y unclutter
    echo "Unclutter entfernt."
fi

# ---------------------------------------------------------
# Watchdog
# ---------------------------------------------------------

if ask "Watchdog deaktivieren"; then
    sudo systemctl stop watchdog
    sudo systemctl disable watchdog
    sudo apt remove -y watchdog

    sudo sed -i 's/watchdog-device/#watchdog-device/' /etc/watchdog.conf
    sudo sed -i 's/max-load-1/#max-load-1/' /etc/watchdog.conf
    sudo sed -i '/ping = 8.8.8.8/d' /etc/watchdog.conf

    echo "Watchdog deaktiviert."
fi

# ---------------------------------------------------------
# Cronjob
# ---------------------------------------------------------

if ask "Cronjob für täglichen Neustart entfernen"; then
    sudo crontab -l | grep -v "/sbin/reboot" | sudo crontab -
    echo "Cronjob entfernt."
fi

# ---------------------------------------------------------
# Journald
# ---------------------------------------------------------

if ask "Journald-Optimierungen rückgängig machen"; then
    sudo sed -i 's/Storage=volatile/#Storage=auto/' /etc/systemd/journald.conf
    sudo sed -i 's/RuntimeMaxUse=50M/#RuntimeMaxUse=/' /etc/systemd/journald.conf
    sudo systemctl restart systemd-journald
    echo "Journald zurückgesetzt."
fi

# ---------------------------------------------------------
# Chromium-Cache
# ---------------------------------------------------------

if ask "Chromium-Cache-Optimierung entfernen"; then
    sudo rm -f "$CHROMIUM_CUSTOM"
    echo "Chromium-Cache wieder normal."
fi

# ---------------------------------------------------------
# tmpfs
# ---------------------------------------------------------

if ask "/tmp RAM-Disk entfernen"; then
    sudo sed -i '/tmpfs \/tmp tmpfs/d' /etc/fstab
    echo "/tmp RAM-Disk entfernt."
fi

# ---------------------------------------------------------
# Updates wieder aktivieren
# ---------------------------------------------------------

if ask "Automatische Updates wieder aktivieren"; then
    sudo systemctl unmask apt-daily.service
    sudo systemctl unmask apt-daily-upgrade.service
    sudo systemctl enable --now apt-daily.service
    sudo systemctl enable --now apt-daily-upgrade.service
    sudo systemctl enable --now unattended-upgrades.service

    echo "Automatische Updates wieder aktiviert."
fi

# ---------------------------------------------------------
# Config löschen
# ---------------------------------------------------------

if ask "Signage-Konfigurationsdatei löschen"; then
    rm -f "$CONFIG_FILE"
    echo "Config gelöscht."
fi

echo "----------------------------------------"
echo " Uninstall abgeschlossen!"
echo " Neustart empfohlen."
echo "----------------------------------------"
