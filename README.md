# Raspberry Pi 5 Digital Signage Setup

Dieses Repository enthält ein vollständiges, professionelles Setup-Skript für Digital Signage auf dem Raspberry Pi 5.


## Installation

### 1. Repository klonen

```bash
git clone https://github.com/EugenSchmigel/signage.git
cd signage

### 2. Dateien ausführbar machen
chmod +x signage-installer-updates-disabled-vx.sh
chmod +x signage-uninstall.sh

./signage-installer-updates-disabled-vx.sh
./signage-uninstall.sh

### 3. Maus ausblenden
sudo raspi-config
-> 6 Advanced Option
-> A7 Wayland
-> W1 X11 


### 4. Neustart
sudo reboot




### 5. jeden Tag um 4 Uhr Chromium neustarten
=== Cronjob ===
Command: crontab -e
0 4 * * * /home/pi/restart-chromium.sh  >> /home/pi/cron-restart-chromium.log 2>
Logs: cat /var/log/cron-restart-chromium.log


### 6. Standby aus

- PMS / Bildschirmschoner deaktivieren (falls Desktop)
  Damit der Bildschirm nicht schwarz wird:
    bash:
      xset -dpms
      xset s off
      xset s noblank

- HDMI‑Hotplug erzwingen, falls Monitor aus → Pi denkt „kein Display“
  bash: sudo nano /boot/firmware/config.txt
  Dann diese Zeile einfügen oder aktivieren:
    hdmi_force_hotplug=1








