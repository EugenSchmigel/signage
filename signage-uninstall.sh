#!/bin/bash
set -e

USER_NAME="$(whoami)"
USER_HOME="/home/$USER_NAME"

CONFIG_FILE="$USER_HOME/signage.conf"
AUTOSTART_DIR="$USER_HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/chromium-kiosk.desktop"
SCREEN_FILE="$AUTOSTART_DIR/screen-settings.desktop"

RESTART_SCRIPT="$USER_HOME/restart-chromium.sh"

CHROMIUM_CUSTOM="/etc/chromium-browser/customizations/01-kiosk"

CHROMIUM_MONITOR="/usr/local/bin/chromium-monitor.sh"
CHROMIUM_MONITOR_SERVICE="/etc/systemd/system/chromium-monitor.service"

echo "----------------------------------------"
echo " Raspberry Pi Signage Uninstaller"
echo "----------------------------------------"
echo

ask() {
    read -p "$1 (j/n): " answer
    [[ "$answer" == "j" ]]
}

# ---------------------------------------------------------
# Autostart entfernen
# ---------------------------------------------------------
if ask "Chromium-Kiosk Autostart entfernen"; then
    rm -f "$AUTOSTART_FILE"
    echo "Autostart entfernt: $AUTOSTART_FILE"
fi

if ask "Bildschirm-Timeout-Einstellungen entfernen"; then
    rm -f "$SCREEN_FILE"
    echo "Screen-Settings entfernt: $SCREEN_FILE"
fi


# ---------------------------------------------------------
# Config-Datei entfernen
# ---------------------------------------------------------
if ask "Signage-Konfigurationsdatei entfernen ($CONFIG_FILE)"; then
    rm -f "$CONFIG_FILE"
    echo "Config entfernt."
fi


# ---------------------------------------------------------
# Chromium Restart Script entfernen
# ---------------------------------------------------------
if ask "Täglichen Chromium-Neustart entfernen"; then
    crontab -l 2>/dev/null | grep -v "restart-chromium.sh" | crontab - || true
    rm -f "$RESTART_SCRIPT"
    echo "Restart-Script und Cronjob entfernt."
fi


# ---------------------------------------------------------
# Chromium Monitor entfernen
# ---------------------------------------------------------
if ask "Chromium-Monitor entfernen"; then
    sudo systemctl stop chromium-monitor.service || true
    sudo systemctl disable chromium-monitor.service || true
    sudo rm -f "$CHROMIUM_MONITOR"
    sudo rm -f "$CHROMIUM_MONITOR_SERVICE"
    sudo systemctl daemon-reload
    echo "Chromium-Monitor entfernt."
fi


# ---------------------------------------------------------
# Watchdog deaktivieren
# ---------------------------------------------------------
if ask "Watchdog deaktivieren und Konfiguration zurücksetzen"; then
    sudo systemctl stop watchdog || true
    sudo systemctl disable watchdog || true

    # Original-Konfiguration wiederherstellen (Kommentare aktivieren)
    sudo sed -i 's/^watchdog-device/#watchdog-device/' /etc/watchdog.conf || true
    sudo sed -i 's/^interval/#interval/' /etc/watchdog.conf || true
    sudo sed -i 's/^watchdog-timeout/#watchdog-timeout/' /etc/watchdog.conf || true
    sudo sed -i 's/^ping =/#ping =/' /etc/watchdog.conf || true
    sudo sed -i 's/^file =/#file =/' /etc/watchdog.conf || true
    sudo sed -i 's/^change =/#change =/' /etc/watchdog.conf || true

    echo "Watchdog deaktiviert und Konfiguration zurückgesetzt."
fi


# ---------------------------------------------------------
# Chromium Cache Customization entfernen
# ---------------------------------------------------------
if ask "Chromium-Cache-RAM-Konfiguration entfernen"; then
    sudo rm -f "$CHROMIUM_CUSTOM"
    echo "Chromium-Cache-Konfiguration entfernt."
fi


# ---------------------------------------------------------
# tmpfs Eintrag entfernen
# ---------------------------------------------------------
if ask "/tmp RAM-Disk wieder entfernen"; then
    sudo sed -i '/tmpfs \/tmp tmpfs/d' /etc/fstab
    echo "/tmp tmpfs Eintrag entfernt."
fi


# ---------------------------------------------------------
# Updates wieder aktivieren
# ---------------------------------------------------------
if ask "Automatische Updates wieder aktivieren"; then
    sudo systemctl unmask apt-daily.service || true
    sudo systemctl unmask apt-daily-upgrade.service || true

    sudo systemctl enable --now apt-daily.service || true
    sudo systemctl enable --now apt-daily-upgrade.service || true
    sudo systemctl enable --now unattended-upgrades.service || true

    echo "Updates wieder aktiviert."
fi


echo
echo "----------------------------------------"
echo " Deinstallation abgeschlossen!"
echo " Ein Neustart wird empfohlen."
echo "----------------------------------------"
