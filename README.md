# MT7925e-BT-Heal
MT7925e-BT-Heal is a small utility to automatically fix the Bluetooth on systems with the **MediaTek MT7925e** Wi-Fi/Bluetooth card when the Bluetooth interface fails to initialize. It works by unloading and reloading the kernel modules for the device, effectively resetting the Bluetooth hardware.  

Tested on **Lenovo Yoga 7 2-in-1 14AKP10 (AMD Strix Point, Fedora 42)**, but should work on any systemd-based Linux distribution with the MT7925e chipset.

---

## Features
- Runs a watchdog script to reinitialize Bluetooth automatically.  
- Fixes missing Bluetooth on boot and after suspend/resume.  
- Provides a systemd service and system-sleep hook.  
- Configurable: choose whether to reload Wi-Fi too.  
- Includes install/uninstall options with a single command.  
- Logs actions to the system journal for easy troubleshooting.  

---

## Installation
Clone the repository and run the setup script:
```bash
git clone https://github.com/moolooite/mt7925e-bt-heal.git
cd mt7925e-bt-heal
sudo ./mt7925e-bt-heal.sh --install
```
This will:
1. Copy the script to /usr/bin/mt7925e-bt-heal.sh
2. Install a systemd service (mt7925e-bt-heal.service)
3. Add a suspend/resume hook (/usr/lib/systemd/system-sleep/mt7925e-bt-heal)
4. Enable the service at boot
5. Reboot once to verify it’s working.

To update, run `git pull` in the cloned folder and then `sudo ./mt7925e-bt-heal.sh --install` again. Your config file is kept.

---

## Uninstall
```bash
sudo ./mt7925e-bt-heal.sh --uninstall
```
This disables the service, removes the files, and cleans up. The config file at /etc/mt7925e-bt-heal.conf is not removed by default so you can reuse it later.

---

## Configuration
Edit /etc/mt7925e-bt-heal.conf to adjust behavior:

REMOVE_WIFI=1 → reload both mt7925e and btusb modules (default).

REMOVE_WIFI=0 → reload only btusb (avoids disrupting Wi-Fi, but less reliable).

WAIT_SECONDS=10 → how long to wait for the Bluetooth adapter to show up before reloading anything (default 10). Raise it if modules get reloaded when Bluetooth would have come up on its own.

---

## Logs
View service logs with:
```bash
sudo ./mt7925e-bt-heal.sh --logs
```
or directly:
```bash
journalctl -u mt7925e-bt-heal.service -n 50
```

---

## Related projects
If your Bluetooth adapter is still there but devices stop connecting, that's a different problem this tool doesn't cover. [bt-zombie-healer](https://github.com/boheastill/bt-zombie-healer) is a separate project aimed at that case.

---

## Credits
This project is based on the solution originally posted on Reddit: ➡️ [MT7925 Bluetooth fix – r/Fedora](https://www.reddit.com/r/Fedora/comments/1k20v5j/mt7925_bluetooth_fix)

That post identified the workaround of reloading the kernel modules:
```bash
sudo modprobe -r btusb mt7925e
sudo modprobe mt7925e
sudo modprobe btusb
```
MT7925e-BT-Heal automates this process and integrates it into systemd so it runs automatically.

---

## Disclaimer
This is a workaround, not a permanent fix. The real solution will come from upstream Linux kernel and firmware updates. Keep your system updated and check for BIOS/driver patches.
