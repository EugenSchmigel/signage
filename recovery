\#!/bin/bash

echo "=== Raspberry Pi Grafik-Reset ==="

# 1\. config.txt zurücksetzen

sudo sed -i '/dtoverlay=/d;/gpu_mem=/d;/hdmi_force_hotplug=/d;/hdmi_group=/d;/hdmi_mode=/d' /boot/config.txt
sudo tee -a /boot/config.txt >/dev/null <<EOF
dtoverlay=vc4-fkms-v3d
gpu_mem=256
hdmi_force_hotplug=1
EOF

# 2\. cmdline.txt bereinigen

sudo sed -i 's/bcm2708_fb[^ \]\*//g' /boot/cmdline.txt

# 3\. Xorg-Konfiguration löschen

sudo rm -f /etc/X11/xorg.conf
sudo rm -f /etc/X11/xorg.conf.d/*.conf

# 4\. Pakete reparieren

sudo apt purge -y xserver-xorg-video-fbdev
sudo apt install --reinstall -y xserver-xorg xserver-xorg-core openbox xinit

# 5\. Autostart deaktivieren

sudo systemctl disable kiosk.service
sudo systemctl set-default multi-user.target

echo "=== Reset abgeschlossen. Bitte jetzt neu starten: sudo reboot ==="
