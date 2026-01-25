#!/bin/bash
set -euo pipefail

USER_NAME="pi"
RESTART_SCRIPT="/home/pi/chromium_restart.sh"
LOGFILE="/home/pi/cron-restart-chromium.log"

echo
echo "---------------------------------------------------------"
echo " Chromium-Neustart – Deinstallation"
echo "---------------------------------------------------------"

ask() {
    local prompt="$1"
    while true; do
        read -r -p "$prompt [j/n]: " yn
        case "$yn" in
            [JjYy]*) return 0 ;;
            [Nn]*)   return 1 ;;
            *)       echo "Bitte j oder n eingeben." ;;
        esac
    done
}

# Cron-Befehl abhängig vom User
if [ "$(id -u)" = "0" ]; then
    CRON_CMD="crontab -u $USER_NAME"
else
    CRON_CMD="crontab"
fi

echo "[INFO] Entferne Cronjob..."

# Cronjob entfernen, falls vorhanden
(
    $CRON_CMD -l 2>/dev/null | grep -v "$RESTART_SCRIPT" || true
) | $CRON_CMD -

echo "[INFO] Cronjob entfernt."

# Restart-Skript löschen
if [ -f "$RESTART_SCRIPT" ]; then
    if ask "Restart-Skript $RESTART_SCRIPT löschen"; then
        rm -f "$RESTART_SCRIPT"
        echo "[INFO] Restart-Skript gelöscht."
    else
        echo "[INFO] Restart-Skript wurde behalten."
    fi
else
    echo "[INFO] Restart-Skript existiert nicht."
fi

# Logfile löschen
if [ -f "$LOGFILE" ]; then
    if ask "Logdatei $LOGFILE löschen"; then
        rm -f "$LOGFILE"
        echo "[INFO] Logdatei gelöscht."
    else
        echo "[INFO] Logdatei wurde behalten."
    fi
else
    echo "[INFO] Logdatei existiert nicht."
fi

echo
echo "---------------------------------------------------------"
echo " Deinstallation abgeschlossen."
echo "---------------------------------------------------------"
