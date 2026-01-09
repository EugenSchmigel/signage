# Raspberry Pi 5 Digital Signage Setup

Dieses Repository enthält ein vollständiges, professionelles Setup-Skript für Digital Signage auf dem Raspberry Pi 5.

## Features

- Minimaler X-Server (kein LXDE)
- Openbox Window Manager
- Chromium im Kiosk-Modus
- Start-Verzögerung (für große Videos)
- Internet-Check vor dem Start
- Browser-Watchdog
- Netzwerk-Watchdog (Online/Offline-Umschaltung)
- Offline-Fallback-Seite
- HDMI-Fixes
- Mauszeiger ausblenden
- WLAN Power Saving deaktivieren
- Täglicher Reboot
- Optimiert für 24/7-Betrieb

## Installation

### 1. Repository klonen

```bash
git clone https://github.com/EugenSchmigel/signage.git
cd signage
chmod +x kiosk-setup.sh
./kiosk-setup.sh

Dann:
sudo reboot


