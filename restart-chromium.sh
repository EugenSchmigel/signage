#!/bin/bash

set -euo pipefail

RESTART_SCRIPT="/home/pi/chromium_restart.sh"
CONFIG_FILE="/home/pi/signage.conf"
CRON_TIME="0 4 * * *"   # täglich um 4:00 Uhr
USER_NAME="pi"          # ggf. anpassen, falls anderes Userkonto.

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

echo
echo "---------------------------------------------------------"
echo " Chromium-Neustart statt Reboot"
echo "---------------------------------------------------------"

# 1. Grundlegende Prüfungen
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[FEHLER] Konfigurationsdatei $CONFIG_FILE nicht gefunden."
    exit 1
fi

if ! command -v chromium-browser >/dev/null 2>&1; then
    echo "[FEHLER] chromium-browser ist nicht installiert oder nicht im PATH."
    exit 1
fi

URL=$(grep '^URL=' "$CONFIG_FILE" | cut -d'=' -f2- || true)
if [ -z "$URL" ]; then
    echo "[FEHLER] Konnte URL aus $CONFIG_FILE nicht lesen (Zeile mit 'URL=' fehlt oder leer)."
    exit 1
fi

if ask "Täglichen Chromium-Neustart um 4 Uhr einrichten"; then

    # 2. Restart-Skript erstellen
    cat <<EOF > "$RESTART_SCRIPT"
#!/bin/bash
set -euo pipefail

CONFIG_FILE="$CONFIG_FILE"
URL=\$(grep '^URL=' "\$CONFIG_FILE" | cut -d'=' -f2- || true)

if [ -z "\$URL" ]; then
    echo "[FEHLER] Konnte URL aus \$CONFIG_FILE nicht lesen."
    exit 1
fi

export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000

echo "[INFO] Beende Chromium..."

pkill -9 chromium 2>/dev/null || true
pkill -9 chromium-browser 2>/dev/null || true
pkill -9 chrome 2>/dev/null || true
sleep 2

rm -f /home/pi/.config/chromium/Singleton*
rm -f /home/pi/.config/chromium/Default/Preferences

echo "[INFO] Starte Chromium neu..."

chromium-browser --kiosk --no-first-run --no-default-browser-check --disable-infobars \
  --disable-session-crashed-bubble --disable-features=TranslateUI \
  --autoplay-policy=no-user-gesture-required --incognito --new-window "\$URL" &
EOF

    chmod +x "$RESTART_SCRIPT"

    # 3. Cronjob robust eintragen (ohne Duplikate)
    echo "[INFO] Trage Cronjob ein..."

    # Falls als root ausgeführt und Cron für User 'pi' gedacht ist:
    CRON_CMD="crontab"
    if [ "\$(id -u)" -eq 0 ] && id "$USER_NAME" >/dev/null 2>&1; then
        CRON_CMD="crontab -u $USER_NAME"
    fi

    # Bestehende Crontab lesen, Eintrag entfernen, neuen hinzufügen
    (
        $CRON_CMD -l 2>/dev/null | grep -v "$RESTART_SCRIPT" || true
        echo "$CRON_TIME $RESTART_SCRIPT"
    ) | $CRON_CMD -

    echo "Chromium-Neustart-Cronjob eingerichtet: täglich 4:00 Uhr."

    # 4. Cronjob automatisch testen (Skript einmal direkt ausführen)
    if ask "Restart-Skript jetzt einmal testweise ausführen"; then
        echo "[INFO] Testlauf des Restart-Skripts..."
        if sudo -u "$USER_NAME" "$RESTART_SCRIPT"; then
            echo "[INFO] Testlauf erfolgreich gestartet (Chromium sollte neu gestartet sein)."
        else
            echo "[WARNUNG] Testlauf des Restart-Skripts ist fehlgeschlagen."
        fi
    fi

else
    echo "Einrichtung des Chromium-Neustart-Cronjobs wurde abgebrochen."
fi
