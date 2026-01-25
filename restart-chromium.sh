#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------
# Einstellungen
# ---------------------------------------------------------
USER_NAME="pi"
RESTART_SCRIPT="/home/pi/chromium_restart.sh"
CONFIG_FILE="/home/pi/signage.conf"
CRON_TIME="0 4 * * *"   # täglich um 4 Uhr
LOGFILE="/home/pi/cron-restart-chromium.log"

# ---------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------
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

# ---------------------------------------------------------
# Start
# ---------------------------------------------------------
echo
echo "---------------------------------------------------------"
echo " Chromium-Neustart statt Reboot"
echo "---------------------------------------------------------"

# ---------------------------------------------------------
# 1. Grundlegende Prüfungen
# ---------------------------------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[FEHLER] Konfigurationsdatei $CONFIG_FILE nicht gefunden."
    exit 1
fi

if ! command -v chromium-browser >/dev/null 2>&1; then
    echo "[FEHLER] chromium-browser ist nicht installiert."
    exit 1
fi

URL=$(grep '^URL=' "$CONFIG_FILE" | cut -d'=' -f2- || true)
if [ -z "$URL" ]; then
    echo "[FEHLER] Konnte URL aus $CONFIG_FILE nicht lesen."
    exit 1
fi

# ---------------------------------------------------------
# 2. Cronjob einrichten
# ---------------------------------------------------------
if ask "Täglichen Chromium-Neustart um 4 Uhr einrichten"; then

    # Restart-Skript erzeugen
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

    echo "[INFO] Trage Cronjob ein..."

    # Logfile anlegen
    touch "$LOGFILE"
    chmod 664 "$LOGFILE"

    # Cron-Befehl abhängig vom User
    if [ "$(id -u)" = "0" ]; then
        CRON_CMD="crontab -u $USER_NAME"
    else
        CRON_CMD="crontab"
    fi

    # Cronjob ohne Duplikate eintragen
    (
        $CRON_CMD -l 2>/dev/null | grep -v "$RESTART_SCRIPT" || true
        echo "$CRON_TIME $RESTART_SCRIPT >> $LOGFILE 2>&1"
    ) | $CRON_CMD -

    echo "Chromium-Neustart-Cronjob eingerichtet: täglich 4:00 Uhr."

    # ---------------------------------------------------------
    # 3. Testlauf (nur wenn grafische Session aktiv)
    # ---------------------------------------------------------
    if ask "Restart-Skript jetzt einmal testweise ausführen"; then

        if pgrep -u "$USER_NAME" lxsession >/dev/null 2>&1; then
            echo "[INFO] Grafische Session erkannt – Testlauf wird ausgeführt..."
            sudo -u "$USER_NAME" DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 "$RESTART_SCRIPT"
            echo "[INFO] Testlauf abgeschlossen."
        else
            echo "[WARNUNG] Keine grafische Session aktiv – Testlauf wird übersprungen."
            echo "Der Cronjob funktioniert trotzdem, aber der Test kann nur im Desktop laufen."
        fi
    fi

else
    echo "Einrichtung des Chromium-Neustart-Cronjobs wurde abgebrochen."
fi
