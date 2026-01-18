#!/bin/bash

echo "=== Raspberry Pi 5 – Wayland Chromium Kiosk Setup ==="

USER="pi"
USER_HOME="/home/$USER"
WEB_SITE= "https://test.test.tech"

# ==========================
# Pakete installieren
# ==========================

sudo apt update
sudo apt install -y chromium-browser unclutter xdotool

# ==========================
# Autologin aktivieren
# ==========================

sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pi --noclear %I \$TERM
EOF

sudo systemctl daemon-reexec

# ==========================
# Wayland-Kiosk-Startscript
# ==========================

cat > "$USER_HOME/kiosk.sh" <<EOF
#!/bin/bash

# Warte kurz, bis Wayland vollständig läuft
sleep 3

chromium-browser --kiosk $WEB_SITE \
  --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required \
  --disable-dev-shm-usage --no-first-run --no-default-browser-check \
  --ozone-platform-hint=auto \
  --enable-features=UseOzonePlatform \
  --start-fullscreen
EOF

chmod +x "$USER_HOME/kiosk.sh"
chown pi:pi "$USER_HOME/kiosk.sh"

# ==========================
# Autostart unter Wayland
# ==========================

mkdir -p "$USER_HOME/.config/autostart"

cat > "$USER_HOME/.config/autostart/kiosk.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Chromium Kiosk
Exec=$USER_HOME/kiosk.sh
X-GNOME-Autostart-enabled=true
EOF


cat > "$USER_HOME/.config/systemd/user/chromium-kiosk.service" <<EOF
[Unit]
Description=Chromium Kiosk Mode
After=graphical-session.target

[Service]
ExecStart=/usr/bin/chromium-browser \
  --kiosk $WEB_SITE \
  --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required \
  --disable-dev-shm-usage --no-first-run --no-default-browser-check \
  --ozone-platform-hint=auto --enable-features=UseOzonePlatform \
  --start-fullscreen
Restart=always
RestartSec=5

[Install]
WantedBy=default.target


EOF


chown -R pi:pi "$USER_HOME/.config"

# ==========================
# Mauszeiger ausblenden
# ==========================

sudo apt install -y unclutter
echo "unclutter -idle 0.1 -root &" >> "$USER_HOME/.bashrc"

echo "=== Setup abgeschlossen. Bitte neu starten: sudo reboot ==="
